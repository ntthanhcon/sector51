# PLAN OPTIMIZE SECTOR51 EA - XỬ LÝ VẤN ĐỀ KẾT QUẢ KHÔNG ĐỒNG NHẤT

## Tóm tắt vấn đề
- Mỗi lần optimize trên MT5 cho kết quả khác nhau
- Lý do chính:
  1. Overfitting quá nhiều parameter
  2. Thiếu quy tắc rõ ràng về bước optimize
  3. Không phân chia dữ liệu out-of-sample

---

## Bước 1: Chuẩn bị dữ liệu và môi trường
1. **Dữ liệu lịch sử**:
   - Sử dụng dữ liệu chất lượng cao (tick data nếu có)
   - Chọn khung thời gian tối ưu (khuyến nghị: H1 HTF + M1 Entry)
   - Chia dữ liệu thành 3 phần:
     - Training (70%): để optimize
     - Validation (20%): để kiểm tra
     - Out-of-sample (10%): để test cuối cùng (không dùng optimize trên phần này)

2. **Cài đặt Strategy Tester**:
   - Model: "Every tick based on real ticks"
   - Use date: đúng với khoảng thời gian đủ dài (ít nhất 6 tháng)
   - Spread: dùng spread thực tế hoặc + 0-2 điểm spread tối đa

---

## Bước 2: Phương pháp optimize (theo các bước)
### Giai đoạn 1: Lock khung thời gian (bắt đầu với cặp khung ổn định:
- Đề xuất cặp khung:
  - HTF: H1
  - Entry: M1
  - (hoặc H4 HTF + M5 Entry)

### Giai đoạn 2: Bật/tắt các filter (nâng tần suất giao dịch)
- Mục tiêu: tìm được số lệnh đủ nhiều nhưng chất lượng
Bắt đầu với tất cả filter TẮT, sau đó thêm dần:
| Input | Giá trị khởi đầu | Mô tả |
|-------|-----------------|-------|
| InpUseHTF_BOS | false | |
| InpUseHTF_OB | false | |
| InpUseHTF_Sweep | false | |
| InpUseEntry_FVG | false | |
| InpUseEntry_OB | false | |
| InpUseEntry_BOS | false | |
| InpUseSessions | false | |
| InpAllowFallbackEntry | true | |

Sau khi có kết quả tốt, bật dần từng filter 1 để tăng chất lượng.

### Giai đoạn 3: Optimize các thông số SL/TP/Risk (kiểm tra các cặp tham số này trước khi optimize nhiều nhất:

#### Thông số cần optimize (theo thứ tự ưu tiên):

1. **[Stop Loss**
   | Input | Start | Step | Stop | Mô tả |
   |-------|-------|------|------|-------|
   | InpSL_BufferPoints | 5 | 1 | 30 | |
   | InpSL_ATR_Mult (nếu dùng ATR) | 1.0 | 0.1 | 3.0 | |

2. **[Take Profit]**
   | Input | Start | Step | Stop | Mô tả |
   |-------|-------|------|------|-------|
   | InpTP_RR_Value | 1.0 | 0.2 | 5.0 | Tỷ lệ risk/reward |

3. **[Position Management]**
   | Input | Start | Step | Stop | Mô tả |
   |-------|-------|------|------|-------|
   | InpUsePartialClose | true/false | | | Bật/tắt partial close |
   | InpPartialPct | 30 | 10 | 70 | % đóng phần trăm đóng tại 1:1 |
   | InpUseBreakEven | true/false | | | Bật/tắt break even |
   | InpBreakEven_RR | 0.8 | 0.2 | 2.0 | RR di chuyển SL về BE |

4. **[Cấu trúc]**
   | Input | Start | Step | Stop | Mô tả |
   |-------|-------|------|------|-------|
   | InpHTF_SwingLB | 2 | 1 | 5 | Lookback swing HTF |
   | InpEntry_SwingLB | 2 | 1 | 5 | Lookback swing Entry |
   | InpATR_Period | 7 | 1 | 20 | Chu kỳ ATR |
   | InpEQ_Threshold | 0.05 | 0.05 | 0.3 | EQ threshold |

---

## Bước 3: Quy tắc chọn kết quả tốt
Không chọn theo profit alone!
Sử dụng các tiêu chí sau (theo thứ tự ưu tiên):

1. **Profit Factor >= 1.5
2. **Recovery Factor >= 2.0
3. **Expected Payoff > 0
4. **Max Drawdown <= 30%
5. **Number of Trades >= 50
6. **Win Rate >= 40%
7. **Avg Win / Avg Loss >= 1.5

---

## Bước 4: Walk-Forward Testing
Sau khi optimize xong, **bắt buộc** test trên dữ liệu out-of-sample (dữ liệu không dùng trong bước optimize.
Nếu kết quả trên out-of-sample tốt (Profit Factor >= 1.2, thì mới dùng được.

---

## Bước 5: Tạo các preset
Tạo **nhiều preset khác nhau cho các thị trường khác nhau:
- Sector51_H1_M1_Aggressive.set
- Sector51_H1_M1_Balanced.set
- Sector51_H1_M1_Conservative.set
- Sector51_H4_M5_Aggressive.set
- Sector51_H4_M5_Balanced.set
- Sector51_H4_M5_Conservative.set

---

## Lưu ý quan trọng
- Không optimize quá nhiều parameter cùng lúc → overfitting!
- Mỗi giai đoạn chỉ optimize 2-3 parameter
- Không thay đổi nhiều nhất 5-10% total parameter trên 1 lần optimize
- Luôn dùng seed cố định nếu có (nếu Strategy Tester có tùy chọn)
- Đừng bao giờ dùng kết quả có ít hơn 50 trades!

