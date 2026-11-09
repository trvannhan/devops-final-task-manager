# Minh chứng Week 4

Ảnh chụp ngày 09–10/11/2026, giờ Việt Nam (UTC+7). Không ảnh nào chứa mật khẩu hoặc giá trị secret. Ảnh 03 có IP riêng của mạng NAT VMware (`192.168.79.x`), không truy cập được từ Internet.

## End-to-end bản final

Bản final là commit merge `c7bb2f4` (Pull Request #3, nhánh `test` → `main`). Lần push này tự chạy pipeline và deploy lên VM, không thao tác tay.

| File | Chứng minh điều gì |
|------|--------------------|
| `01-pipeline-final.png` | Pipeline #18 "Merge pull request #3" trên `main`, commit `c7bb2f4`: Test (28s) → Build & push image (33s) → Deploy to Ubuntu VM (1m 17s) đều xanh, tổng 2m 32s |
| `02-smoke-test-final.png` | Bước smoke test của job Deploy: `/health` qua Nginx trả `{"database":"connected","status":"ok","version":"c7bb2f4"}`, đúng mã commit vừa push |
| `03-web-final.png` | Trang web từ Windows qua `:8080`: chân trang hiện `Database connected · vc7bb2f4`, dữ liệu các tuần trước vẫn còn |

Dòng `curl: (22) ... 502` trong ảnh 02 không phải lỗi: ngay sau khi container app được tạo lại, Nginx chưa gọi được app nên trả 502. Smoke test thử lại tối đa 30 lần, cách nhau 2 giây, và thành công ở lần kế tiếp khi app đã sẵn sàng.
