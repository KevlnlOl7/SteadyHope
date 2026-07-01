#!/usr/bin/env python3
"""
severity_rf.py — 震顫嚴重度 Random Forest (真實 PD 資料)
================================================================
用 4 個真實 PD 資料集(TIM-Tremor / PdAssist / IMU-Wild / PD-BioStamp)訓練
「震顫嚴重度 0-3」分類器, 供辨識/gating 與數位生物標記使用。

資料: 加速度 [n,128,3] @ 50Hz, 標籤 0-3 (0=無震顫, 1-3 遞增)。約 24,000 視窗。
特徵: 三軸加速度視窗的震顫帶頻譜特徵 (rest/postural tremor 適用; DTW-RAM 不適用此資料)。
評估: segment-level split (同 segment 不跨訓練/測試, 防資料洩漏)。

類別不平衡處理 (計畫書的 GAN 動機):
  - SMOTE (特徵空間, 手刻)         → 對「特徵向量 RF」有效 (推薦, 見下方實測)
  - 條件式 GAN (torch, WGAN-GP)     → 對 9 維特徵沒贏過 SMOTE (誠實紀錄)
  - ★ raw-signal GAN (生成 128x3 原始訊號) = 後半段進階, 本檔未實作

實測 (segment-level, 測試集不擴增):
  無擴增   平衡acc 48.7 | 有無震顫 71.8
  SMOTE    平衡acc 60.2 | 有無震顫 81.1   ← 少數類 recall 幾乎翻倍
  GAN(特徵) 平衡acc 49.0 | 有無震顫 72.8   ← 約等於 baseline

需求: numpy, scikit-learn, torch(可選, 僅 GAN 用)。
資料路徑見 BASE (預設指向專案根目錄 Copy/; dataset 未入庫, 見 README)。
================================================================
"""
import numpy as np, glob, os, warnings
warnings.filterwarnings('ignore')
from numpy.fft import rfft, rfftfreq
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GroupShuffleSplit
from sklearn.metrics import balanced_accuracy_score, accuracy_score, confusion_matrix, recall_score

FS = 50.0; NW = 128
_HERE = os.path.dirname(os.path.abspath(__file__))
# 資料集在專案根目錄外的 Copy/ (未入庫; 若搬移請改此路徑)
BASE = os.path.join(_HERE, '..', '..', '..', 'Copy', 'Parkinson-s-Disease-Tremor-Dataset-main')
DSETS = ['Tim-Tremor', 'PdAssist', 'IMU-Wild', 'PD-BioStamp']
FEAT_NAMES = ['rms','r3-8','r4-6','dom_f','sp_ent','axX','axY','axZ','r8-15']
# gating: 嚴重度 -> control_sim 的 PID gain_scale
GATING = {0: 0.0, 1: 0.7, 2: 1.0, 3: 1.4}   # 0=不出力 … 3=高增益(精細支撐)


def feat_window(w):
    """w:[128,3] 加速度 -> 9 維震顫帶頻譜特徵."""
    w = w - w.mean(0)
    mag = np.sqrt((w**2).sum(1)); mag = mag - mag.mean()
    X = np.abs(rfft(mag)); f = rfftfreq(NW, 1/FS); P = X**2; tot = P.sum() + 1e-12
    band = (f >= 3) & (f <= 8)
    dom = float(f[band][np.argmax(X[band])]) if band.any() else 0.0
    p = P/tot; ent = float(-(p[p > 0]*np.log(p[p > 0])).sum())
    ax = []
    for a in range(3):
        s = w[:, a] - w[:, a].mean(); Pa = np.abs(rfft(s))**2
        ax.append(Pa[(f >= 3) & (f <= 8)].sum()/(Pa.sum()+1e-12))
    return [mag.std(), P[(f >= 3) & (f < 8)].sum()/tot, P[(f >= 4) & (f < 6)].sum()/tot,
            dom, ent, *ax, P[(f >= 8) & (f < 15)].sum()/tot]


def load_all():
    """回傳 特徵X, 標籤y, group(dataset:segment 用於防洩漏 split)."""
    Xs, ys, g = [], [], []
    for ds in DSETS:
        for xf in sorted(glob.glob(os.path.join(BASE, ds, '*-X.npy'))):
            gid = f"{ds}:{os.path.basename(xf).split('-')[0]}"
            x = np.load(xf); y = np.load(xf.replace('-X.npy', '-Y.npy')).reshape(-1)
            for i in range(len(x)):
                Xs.append(feat_window(x[i])); ys.append(int(y[i])); g.append(gid)
    return np.array(Xs), np.array(ys), np.array(g)


def smote(X, y, target):
    """特徵空間 SMOTE: 每個少數類以 k 近鄰內插補到 target 筆."""
    rng = np.random.default_rng(0); Xo, yo = [X], [y]
    for c in np.unique(y):
        Xc = X[y == c]; need = target - len(Xc)
        if need <= 0 or len(Xc) < 2:
            continue
        d = ((Xc[:, None, :] - Xc[None, :, :])**2).sum(-1); np.fill_diagonal(d, np.inf)
        knn = np.argsort(d, 1)[:, :min(5, len(Xc)-1)]
        idx = rng.integers(0, len(Xc), need)
        nb = knn[idx, rng.integers(0, knn.shape[1], need)]
        lam = rng.random((need, 1))
        Xo.append(Xc[idx] + lam*(Xc[nb] - Xc[idx])); yo.append(np.full(need, c))
    return np.vstack(Xo), np.concatenate(yo)


def gan_augment(X, y, target, epochs=1500):
    """條件式 GAN (torch, WGAN-GP) 生成少數類特徵. 注意: 實測未勝過 SMOTE."""
    import torch, torch.nn as nn
    torch.manual_seed(0)
    mu, sd = X.mean(0), X.std(0)+1e-6; Xn = (X-mu)/sd
    d = X.shape[1]; nc = int(y.max()+1); zc = 16
    G = nn.Sequential(nn.Linear(zc+nc, 64), nn.ReLU(), nn.Linear(64, 64), nn.ReLU(), nn.Linear(64, d))
    D = nn.Sequential(nn.Linear(d+nc, 64), nn.LeakyReLU(0.2), nn.Linear(64, 64), nn.LeakyReLU(0.2), nn.Linear(64, 1))
    oG = torch.optim.Adam(G.parameters(), 2e-4, betas=(0.5, 0.9))
    oD = torch.optim.Adam(D.parameters(), 2e-4, betas=(0.5, 0.9))
    Xt = torch.tensor(Xn, dtype=torch.float32); Yt = torch.eye(nc)[y]
    for ep in range(epochs):
        idx = torch.randint(0, len(Xt), (256,)); xr, cr = Xt[idx], Yt[idx]
        z = torch.randn(256, zc); xf = G(torch.cat([z, cr], 1)).detach()
        eps = torch.rand(256, 1); xh = (eps*xr + (1-eps)*xf).requires_grad_(True)
        dh = D(torch.cat([xh, cr], 1))
        gp = torch.autograd.grad(dh.sum(), xh, create_graph=True)[0].norm(2, 1)
        lossD = D(torch.cat([xf, cr], 1)).mean() - D(torch.cat([xr, cr], 1)).mean() + 10*((gp-1)**2).mean()
        oD.zero_grad(); lossD.backward(); oD.step()
        if ep % 5 == 0:
            z = torch.randn(256, zc)
            lossG = -D(torch.cat([G(torch.cat([z, cr], 1)), cr], 1)).mean()
            oG.zero_grad(); lossG.backward(); oG.step()
    Xo, yo = [X], [y]
    for c in np.unique(y):
        need = target - int((y == c).sum())
        if need <= 0:
            continue
        z = torch.randn(need, zc); cc = torch.eye(nc)[np.full(need, c)]
        with torch.no_grad():
            gen = G(torch.cat([z, cc], 1)).numpy()*sd + mu
        Xo.append(gen); yo.append(np.full(need, c))
    return np.vstack(Xo), np.concatenate(yo)


def eval_rf(Xtr, ytr, Xte, yte, tag):
    rf = RandomForestClassifier(n_estimators=300, class_weight='balanced',
                                random_state=0, n_jobs=-1).fit(Xtr, ytr)
    yp = rf.predict(Xte)
    bal = balanced_accuracy_score(yte, yp)*100; acc = accuracy_score(yte, yp)*100
    rec = recall_score(yte, yp, labels=[0, 1, 2, 3], average=None, zero_division=0)*100
    binb = balanced_accuracy_score((yte > 0).astype(int), (yp > 0).astype(int))*100
    print(f"{tag:12s} | acc {acc:5.1f} | 平衡 {bal:5.1f} | 有無震顫 {binb:5.1f} | recall {np.round(rec).astype(int)}")
    return rf


if __name__ == "__main__":
    if not os.path.isdir(BASE):
        raise SystemExit(f"找不到資料集: {BASE}\n請把 BASE 改成 Parkinson-s-Disease-Tremor-Dataset-main 的實際路徑。")
    print("載入 4 資料集 + 特徵擷取 ...")
    X, y, g = load_all()
    lbl, cnt = np.unique(y, return_counts=True)
    print(f"總樣本={len(y)}  標籤={dict(zip(lbl.tolist(), cnt.tolist()))}  segments={len(np.unique(g))}")
    tr, te = next(GroupShuffleSplit(1, test_size=0.3, random_state=0).split(X, y, g))
    Xtr, ytr, Xte, yte = X[tr], y[tr], X[te], y[te]
    tgt = int(np.bincount(ytr).max())

    print("\n=== 不平衡擴增比較 (segment-level split; 測試集不擴增) ===")
    eval_rf(Xtr, ytr, Xte, yte, '無擴增')
    Xs, ys2 = smote(Xtr, ytr, tgt); rf = eval_rf(Xs, ys2, Xte, yte, 'SMOTE(推薦)')
    try:
        Xg, yg = gan_augment(Xtr, ytr, tgt); eval_rf(Xg, yg, Xte, yte, 'GAN(特徵)')
    except ImportError:
        print("GAN(特徵)    | (未裝 torch, 略過)")

    print("\n混淆矩陣 (SMOTE 版, 列=真實 0-3):")
    C = confusion_matrix(yte, rf.predict(Xte), labels=[0, 1, 2, 3])
    for i in range(4):
        print("  " + " ".join(f"{C[i, j]:5d}" for j in range(4)))
    print("\n特徵重要度:")
    for nm, imp in sorted(zip(FEAT_NAMES, rf.feature_importances_), key=lambda a: -a[1]):
        print(f"  {nm:8s} {imp:.3f}")
    print(f"\ngating: 嚴重度 -> PID gain_scale = {GATING}")
