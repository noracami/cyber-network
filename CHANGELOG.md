# Changelog

## 0.1.0 (2026-10-15)

第一個用 release 流程發的版本。之前是 push main 就部署（先到 wisp VM，後來 GKE 手動改 digest），
這一版的程式跟之前線上跑的一樣（ea3d120），只換了部署方式。

### 修正

* 部署改到 Dokploy：release PR 觸發部署，拿掉 wisp webhook ([#1](https://github.com/noracami/cyber-network/pull/1))
