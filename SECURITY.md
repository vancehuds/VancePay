# 安全政策

语言：[中文](SECURITY.md) | [English](SECURITY.en.md)

## 支持版本

安全修复会优先面向 VancePay 的最新发布版本处理。

## 报告漏洞

如果项目托管在 GitHub，请优先通过 GitHub Security Advisories 私下报告安全问题；也可以通过仓库所有者资料中的联系方式联系维护者。

不要在公开 issue 中发布可利用细节、token、私服配置或玩家数据。

报告时请包含：

- 受影响版本或 commit
- 与问题相关的资源配置
- 清晰的复现步骤
- 预期影响范围

## 密钥

KOOK 凭据、VanceFiveMLog API Key、数据库凭据和服务器专属 convar 应保存在 `server.cfg` 或部署平台的密钥管理中，不要提交到本仓库。
