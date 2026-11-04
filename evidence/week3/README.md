# Minh chứng Week 3

Ảnh chụp ngày 04/11/2026, giờ Việt Nam (UTC+7). Địa chỉ IP riêng đã được che; không ảnh nào chứa mật khẩu hoặc giá trị secret.

Lưu ý múi giờ: Prometheus hiển thị theo UTC, nên trong ảnh 06 mốc thời gian lệch 7 tiếng so với giờ Việt Nam. Khi thuyết minh, dùng giờ Việt Nam.

| File | Chứng minh điều gì |
|------|--------------------|
| `01-dashboard-binh-thuong.png` | Dashboard "Task Manager – Tổng quan hệ thống" lúc hệ thống bình thường: Web qua Nginx và Container app đều UP, 0 cảnh báo đang bật, CPU và RAM ổn định |
| `02-prometheus-binh-thuong.png` | Prometheus `/alerts` lúc bình thường: 7 luật cảnh báo đều INACTIVE |
| `03-prometheus-firing.png` | Sau khi dừng container app (`docker compose stop app`): `AppContainerDown` và `AppDownViaNginx` chuyển sang FIRING |
| `04-alertmanager-firing.png` | Alertmanager nhận cảnh báo, nhóm `web-ui` hiển thị 1 cảnh báo `AppContainerDown` (severity critical). `AppDownViaNginx` bị ẩn nhờ luật inhibit |
| `05-dashboard-su-co.png` | Dashboard trong lúc sự cố: vùng đỏ ở "Trạng thái /health theo thời gian" cho thấy cả hai đường kiểm tra đều lỗi; thời gian phản hồi vượt 1 giây ở hai thời điểm |
| `06-prometheus-lich-su-canh-bao.png` | Truy vấn `ALERTS{alertstate="firing"}` theo thời gian: hai cảnh báo cùng bật trong khoảng sự cố, rồi tắt khi hệ thống khôi phục |
| `07-prometheus-resolved.png` | Sau khi `docker compose up -d app`: các cảnh báo trở về INACTIVE |
| `08-alertmanager-resolved.png` | Alertmanager không còn cảnh báo đang bật |

Chuỗi sự cố đã kiểm chứng: dừng app → cảnh báo bật (ảnh 03, 04) → khôi phục → cảnh báo tắt (ảnh 07, 08). Ảnh 05 và 06 ghi lại khoảng thời gian có lỗi, trong đó có lỗi xác thực database được xử lý theo playbook mục 3.
