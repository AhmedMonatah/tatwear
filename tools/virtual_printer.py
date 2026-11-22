"""
Virtual Thermal Printer (محاكي طابعة الفواتير الحرارية)
-------------------------------------------------------
يستقبل أوامر الطباعة عبر Bluetooth (COM Port) أو عبر شبكة TCP (Port 9100).
يدعم أوامر:
- CPCL (طابعات Intermec PR3, PR2, Zebra)
- ESC/POS (طابعات الكاشير الصينية و Xprinter)

ويقوم بتحويل البيانات المستلمة إلى صورة فاتورة PNG ويفتحها تلقائياً على شاشة الكمبيوتر!
"""

import sys
import os
import time
import socket
import select
from PIL import Image

def decode_cpcl(data: bytes, output_path: str):
    """فك تشفير أوامر CPCL واستخراج الصورة أو النصوص مع دعم الشرائح المتعددة Slices"""
    print("\n[CPCL Parser] تم اكتشاف أمر CPCL (Intermec / Zebra)...")
    
    # البحث عن أبعاد الصفحة من رأس CPCL: ! 0 200 200 <height> 1
    page_height = 0
    page_width = 576
    try:
        header_line = data[:100].split(b'\n')[0].decode('ascii', errors='ignore').strip()
        parts = header_line.split()
        if len(parts) >= 5 and parts[0] == '!':
            page_height = int(parts[4])
    except Exception:
        pass
        
    pw_pos = data.find(b'PAGE-WIDTH ')
    if pw_pos != -1:
        try:
            pw_line = data[pw_pos:pw_pos+30].split(b'\n')[0].decode('ascii', errors='ignore').strip()
            page_width = int(pw_line.split()[1])
        except Exception:
            pass

    # البحث عن جميع أوامر EG (Expanded Graphics)
    eg_indices = []
    idx = 0
    while True:
        pos = data.find(b'EG ', idx)
        if pos == -1:
            break
        eg_indices.append(pos)
        idx = pos + 3

    if eg_indices:
        print(f"[CPCL] تم العثور على {len(eg_indices)} شريحة رسومية (EG Slices)...")
        # حساب أقصى ارتفاع إذا لم يكن محدداً في الرأس
        max_y = page_height if page_height > 0 else 1000
        img = Image.new('1', (page_width, max_y), 1)
        pixels = img.load()

        found_valid_slice = False
        for eg_pos in eg_indices:
            try:
                header_end = data.find(b'\n', eg_pos)
                if header_end == -1:
                    header_end = eg_pos + 50
                header_line = data[eg_pos:header_end].decode('ascii', errors='ignore').strip()
                parts = header_line.split()
                if len(parts) >= 5:
                    byte_w = int(parts[1])
                    h = int(parts[2])
                    x_start = int(parts[3])
                    y_start = int(parts[4])

                    prefix_len = len(f"EG {parts[1]} {parts[2]} {parts[3]} {parts[4]} ")
                    data_start = eg_pos + prefix_len
                    data_len = byte_w * h
                    raw_slice = data[data_start:data_start + data_len]

                    # توسيع الصورة إذا كان y يتجاوز الارتفاع
                    if y_start + h > img.height:
                        new_img = Image.new('1', (page_width, y_start + h + 50), 1)
                        new_img.paste(img, (0, 0))
                        img = new_img
                        pixels = img.load()

                    for sy in range(min(h, len(raw_slice) // byte_w)):
                        py = y_start + sy
                        for b_idx in range(byte_w):
                            b_val = raw_slice[sy * byte_w + b_idx]
                            for bit in range(8):
                                px = x_start + b_idx * 8 + bit
                                if px < img.width and py < img.height:
                                    is_black = (b_val & (0x80 >> bit)) != 0
                                    pixels[px, py] = 0 if is_black else 1
                    found_valid_slice = True
            except Exception as e:
                print(f"[CPCL Slice Warning] {e}")

        if found_valid_slice:
            img.save(output_path)
            print(f"✅ تم حفظ صورة الفاتورة بنجاح: {output_path}")
            return True
            
    # إذا لم توجد صورة EG، نطبع النصوص
    try:
        text_content = data.decode('utf-8', errors='ignore')
        for line in text_content.splitlines():
            if line.strip():
                print(f"   | {line.strip()}")
    except Exception:
        pass
    return False

def decode_escpos(data: bytes, output_path: str):
    """فك تشفير أوامر ESC/POS واستخراج الصورة النقطية (GS v 0)"""
    print("\n[ESC/POS Parser] تم اكتشاف أوامر ESC/POS القياسية...")
    gs_v_pos = data.find(b'\x1dv0\x00')
    if gs_v_pos != -1:
        try:
            # استخراج أبعاد الصورة
            xL = data[gs_v_pos + 4]
            xH = data[gs_v_pos + 5]
            yL = data[gs_v_pos + 6]
            yH = data[gs_v_pos + 7]
            
            byte_width = xL + (xH << 8)
            height = yL + (yH << 8)
            width = byte_width * 8
            
            data_start = gs_v_pos + 8
            data_len = byte_width * height
            raw_bytes = data[data_start:data_start + data_len]
            
            print(f"[ESC/POS] العرض: {width}px، الارتفاع: {height}px، حجم الصورة: {len(raw_bytes)}/{data_len} بايت")
            
            if len(raw_bytes) > 0:
                img = Image.new('1', (width, height), 1)
                pixels = img.load()
                for y in range(min(height, len(raw_bytes) // byte_width)):
                    for b_idx in range(byte_width):
                        byte_val = raw_bytes[y * byte_width + b_idx]
                        for bit in range(8):
                            x = b_idx * 8 + bit
                            if x < width:
                                is_black = (byte_val & (0x80 >> bit)) != 0
                                pixels[x, y] = 0 if is_black else 1
                
                img.save(output_path)
                print(f"✅ تم حفظ صورة الفاتورة بنجاح: {output_path}")
                return True
        except Exception as e:
            print(f"[ESC/POS Parser Error] {e}")
            
    return False

def process_received_data(buffer: bytes):
    """معالجة البيانات وعرض التقرير والصورة"""
    print(f"\n==================================================")
    print(f"📥 تم استلام إرسالية طباعة جديدة: {len(buffer)} بايت!")
    print(f"==================================================")
    
    # حفظ البايتات الخام في ملف للفحص الدقيق
    raw_file = os.path.join(os.path.dirname(__file__), "last_received_job.bin")
    with open(raw_file, "wb") as f:
        f.write(buffer)
    print(f"💾 تم حفظ البايتات الخام في: {raw_file}")
    
    # أول 100 حرف لمعاينة الرأس
    header_preview = buffer[:150].decode('latin1', errors='replace').replace('\r', '\\r').replace('\n', '\\n')
    print(f"🔍 رأس البيانات المستلمة:\n{header_preview}\n")
    
    timestamp = int(time.time())
    output_png = os.path.join(os.path.dirname(__file__), f"virtual_receipt_{timestamp}.png")
    
    success = False
    if b'!' in buffer[:20] or b'EG ' in buffer or b'PAGE-WIDTH' in buffer:
        success = decode_cpcl(buffer, output_png)
    elif b'\x1dv0' in buffer or b'\x1b@' in buffer:
        success = decode_escpos(buffer, output_png)
    else:
        print("[!] لم يتم التعرف على بروتوكول محدد (تم حفظ البيانات الخام للفحص).")
        try:
            print("نص الرسالة المستلمة:")
            print(buffer.decode('utf-8', errors='ignore'))
        except Exception:
            pass

    if success and os.path.exists(output_png):
        print(f"\n🎉 جارٍ فتح صورة الفاتورة على شاشة الكمبيوتر ({output_png})...")
        try:
            os.startfile(output_png)
        except Exception as e:
            print(f"[Notice] تعذّر فتح الصورة تلقائياً: {e}")

def listen_serial(port_name: str):
    """الاستماع على منفذ تسلسلي / منفذ بلوتوث COM Port"""
    import serial
    print(f"\n[Bluetooth Listener] جارٍ فتح منفذ البلوتوث ({port_name})...")
    try:
        ser = serial.Serial(port_name, baudrate=115200, timeout=1.0)
    except Exception as e:
        print(f"❌ تعذّر فتح منفذ {port_name}: {e}")
        return

    print(f"🟢 [جاهز] المحاكي يستمع الآن على المنفذ {port_name}.")
    print("👉 افتح التطبيق في الهاتف واضغط طباعة واختر هذا الجهاز.")
    print("اضغط Ctrl+C للإيقاف في أي وقت.\n")

    buffer = bytearray()
    last_recv_time = None

    try:
        while True:
            waiting = ser.in_waiting
            if waiting > 0:
                chunk = ser.read(waiting)
                buffer.extend(chunk)
                last_recv_time = time.time()
                sys.stdout.write(f"\r📥 تم استلام {len(buffer)} بايت حتى الآن...")
                sys.stdout.flush()
            else:
                # إذا توقف الإرسال لأكثر من ثانية ونصف، نعتبر أمر الطباعة انتهى ونعالجه
                if last_recv_time is not None and (time.time() - last_recv_time > 1.5):
                    print()
                    process_received_data(bytes(buffer))
                    buffer.clear()
                    last_recv_time = None
                    print(f"\n🟢 المحاكي جاهز لاستلام طباعة أخرى على {port_name}...")
                time.sleep(0.05)
    except KeyboardInterrupt:
        print("\nتم إيقاف المحاكي.")
    finally:
        ser.close()

def listen_tcp(port=9090):
    """الاستماع على منفذ شبكة محلي (TCP Port 9090 - Raw Print)"""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    # الحصول على IP المحلي للجهاز
    hostname = socket.gethostname()
    local_ip = "127.0.0.1"
    try:
        local_ip = socket.gethostbyname(hostname)
    except Exception:
        pass

    s.bind(('0.0.0.0', port))
    s.listen(1)
    print(f"\n🟢 [المحاكي جاهز ويعمل الآن]")
    print(f"👉 المنفذ النشط: {port}")
    print(f"👉 إذا كان الهاتف متصلاً بالـ USB: سيتم الاستلام تلقائياً عبر ADB!")
    print(f"👉 إذا كان الهاتف عبر الواي فاي: عنوان اللاب توب هو {local_ip}:{port}")
    print(f"في انتظار استلام الفاتورة من التطبيق...\n")

    buffer = bytearray()
    try:
        while True:
            conn, addr = s.accept()
            print(f"\n📱 اتصال جديد وارد من الهاتف ({addr[0]}:{addr[1]})...")
            conn.settimeout(2.0)
            while True:
                try:
                    data = conn.recv(4096)
                    if not data:
                        break
                    buffer.extend(data)
                    sys.stdout.write(f"\r📥 استلام البيانات: {len(buffer)} بايت...")
                    sys.stdout.flush()
                except socket.timeout:
                    break
                except Exception:
                    break
            conn.close()
            if buffer:
                print()
                process_received_data(bytes(buffer))
                buffer.clear()
                print(f"\n🟢 المحاكي مستعد لاستلام فاتورة أخرى في أي وقت...")
    except KeyboardInterrupt:
        print("\nتم إيقاف المحاكي.")
    finally:
        s.close()

def main():
    print("=" * 60)
    print("🖨️  محاكي الطابعة الحرارية الافتراضية (Virtual Thermal Printer)")
    print("=" * 60)
    
    import serial.tools.list_ports as lp
    ports = list(lp.comports())
    
    print("\nاختر طريقة التشغيل:")
    print("1. التشغيل الفوري عبر USB / WiFi (موصى به - لا يحتاج أي إعدادات) [افتراضي]")
    print("2. الاستماع عبر منفذ بلوتوث تسلسلي (COM Port)")
    print("3. فتح إعدادات البلوتوث الكلاسيكية في ويندوز")
    
    try:
        choice = input("\nأدخل رقم الخيار [اضغط Enter للخيار 1]: ").strip()
    except EOFError:
        choice = '1'
        
    if not choice or choice == '1':
        listen_tcp(9090)
    elif choice == '3':
        print("\nجارٍ فتح إعدادات البلوتوث...")
        os.system("control bthprops.cpl")
    else:
        if ports:
            port_to_use = ports[0].device
            if len(ports) > 1:
                idx = input(f"اختر رقم المنفذ (1-{len(ports)}) [افتراضي 1]: ").strip()
                if idx.isdigit() and 1 <= int(idx) <= len(ports):
                    port_to_use = ports[int(idx) - 1].device
            listen_serial(port_to_use)
        else:
            p_name = input("أدخل اسم منفذ البلوتوث (مثال: COM4): ").strip()
            if p_name:
                listen_serial(p_name.upper())
            else:
                listen_tcp(9090)

if __name__ == '__main__':
    main()
