# Svid v1.0.0 — Hướng dẫn cài đặt (Tester)

## Cài đặt
1. Mở file **Svid-1.0.0-macos.dmg**
2. Kéo **svid.app** vào thư mục **Applications**
3. Mở app từ Applications

## Nếu bị chặn bởi Gatekeeper
App chưa có Apple certificate nên macOS sẽ cảnh báo. Xử lý 1 lần:

- Vào **System Settings → Privacy & Security** → tìm dòng "svid was blocked" → bấm **Open Anyway**
- Hoặc mở Terminal chạy: `sudo xattr -rd com.apple.quarantine /Applications/svid.app`

## Khuyến nghị
- Cài **Python 3.10+** để app parse URL nhanh nhất (1-2s): `brew install python3`
- Không có Python vẫn hoạt động, nhưng lần parse đầu sẽ chậm hơn (~15-20s)

## Nếu đã cài bản cũ
Xóa bản cũ trước khi cài mới — mở Terminal chạy:
```
rm -rf /Applications/svid.app ~/Library/Application\ Support/com.svid.app
```
