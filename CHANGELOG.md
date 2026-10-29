# 更新紀錄

## v0.1.1

- Windows：依實際讀入長度檢查 E0 回覆，拒絕缺少資料的短封包，避免補零資料被當成讀數。
- Windows：握手或讀取收到 `FE` 拒絕回覆時立即報錯。
- Windows：使用經過時間控制讀取期限，期限內持續略過不匹配的回覆，取消原本最多六份回覆的限制。
- Windows：逾時請求取消掛起的讀取；保留 Query 的 handle 取消與清理。
- Windows：原始封包輸出只含實際取得的 bytes，完整解析成功後才設定 `ok=true`。
- 新增九個不接硬體的 Windows 傳輸測試，包含短包、拒絕、第七份有效回覆與逾時取消。
- 新增四個 Windows 解析情境，核對原捕獲讀數、無 report ID、最小有效長度與短包失敗；Linux 四個既有解析測試保持通過。

此版維持單次命令列介面和 JSON 欄位。新修正經離線測試與 Rea MCP 靜態分析；未重新進行電源實機測試，沒有新增高頻常駐模式，也沒有保證硬體更新 Hz。Linux 程式保持原版本，仍未經 Linux 實機驗證。`watts_in` 仍為推算值。

## v0.1.0

首個公開版本。Windows PowerShell 與 Linux Python USB HID 單次讀取器；Windows 原版曾在兩台 Ai1300P 主機驗證。
