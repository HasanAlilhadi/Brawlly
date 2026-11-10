# تشغيل Brawlly على حاسبة Windows جديدة (والشاشة السودة)

هذا الملف يشرح شنو لازم تنزّل على أي حاسبة جديدة حتى تفتح المشروع وتشغّل اللعبة (F5 / الديباك)،
وشلون تحل مشكلة **الشاشة السودة**.

---

## 1. الأشياء الضرورية

| الشي | ليش | ملاحظة |
|---|---|---|
| **Godot 4.7.2 stable – Standard (مو .NET)** | محرك المشروع | لازم **نفس النسخة بالضبط** (4.7.2). نسخة أقدم ممكن تخرّب المشاهد أو تطلع شاشة سودة. نزّل نسختين من نفس الصفحة: `Godot_v4.7.2-stable_win64.exe` و `Godot_v4.7.2-stable_win64_console.exe` (الثانية تطلّع الأخطاء بنافذة سودة نقرأ منها). |
| **أحدث درايفر لكارت الشاشة** | اللعبة ترسم بـ Vulkan / Direct3D 12 | أهم خطوة. نزّله من موقع الشركة نفسها مو من Windows Update: NVIDIA (GeForce Experience / nvidia.com/drivers)، AMD (amd.com/support)، Intel (intel.com → Driver & Support Assistant). |
| **Windows 10 أو 11، 64-bit** | Godot 4 ما يشتغل على 32-bit | |
| **Git** (git-scm.com) | حتى تسحب المشروع | المشروع ما يستخدم Git LFS، فـ `git clone` العادي يكفي. |

**مو ضروريات** (بس لأدوات بناء الموديلات والقوالب): Python 3 و Blender (لـ `tools/blender_*.py`)، و export
templates 4.7.2 (بس على الحاسبة الي تطلّع منها `Brawlly.exe`).

---

## 2. أول فتح للمشروع

1. اسحب المشروع: `git clone https://github.com/HasanAlilhadi/Brawlly.git` ثم `git checkout feat/conquest-mode`.
2. شغّل Godot 4.7.2 ← **Import** ← اختار `project.godot`.
3. **أول فتح ياخذ وكت** (عدة دقايق): Godot يبني مجلد `.godot/` (ما ينحفظ بـ git) ويستورد كل الأصول.
   خلي شريط التقدّم يخلص، لا تسده.
4. اضغط **F5**: تطلع القائمة الرئيسية (`main_menu.tscn`).

---

## 3. إذا طلعت شاشة سودة — جرّب بهذا الترتيب

المشروع مضبوط على الرسّام **Mobile**، وهو يحتاج **Vulkan** أو **Direct3D 12**. أغلب حالات الشاشة السودة
تصير من كارت شاشة قديم أو درايفر ما يدعمهم صح (خصوصاً Intel HD القديم ومعه درايفر Windows الافتراضي).

### أ) حدّث درايفر كارت الشاشة
هذا يحل أغلب الحالات. بعد التحديث سوّي Restart للحاسبة.

### ب) لابتوب بيه كارتين (Intel + NVIDIA/AMD)
Windows Settings ← System ← Display ← **Graphics** ← Browse ← اختار `Godot_v4.7.2-stable_win64.exe`
← Options ← **High performance** ← Save. وسوّي نفس الشي للعبة المصدّرة `Brawlly.exe`.

### ج) غيّر درايفر الرسم من سطر الأوامر
افتح PowerShell بمجلد Godot وجرّب هالأوامر وحدة وحدة (بدّل المسار إذا المشروع بمكان ثاني):

```powershell
# 1) Direct3D 12 بدال Vulkan
.\Godot_v4.7.2-stable_win64.exe --rendering-driver d3d12 --path "D:\games\dev\Brawlly" -e

# 2) Vulkan صراحةً (إذا D3D12 هو الي يخرب)
.\Godot_v4.7.2-stable_win64.exe --rendering-driver vulkan --path "D:\games\dev\Brawlly" -e

# 3) آخر حل: OpenGL (رسّام Compatibility؛ يشتغل على أي كارت تقريباً بس الشكل أبسط شوية)
.\Godot_v4.7.2-stable_win64.exe --rendering-method gl_compatibility --rendering-driver opengl3 --path "D:\games\dev\Brawlly" -e
```

`-e` يفتح المحرر. إذا تريد تشغّل اللعبة مباشرة بدون محرر، شيل `-e`.
الأمر الي يشتغل سوّيله **Shortcut** على سطح المكتب: كلك يمين على Godot.exe ← Create shortcut ← Properties ←
وبمربع **Target** ضيف الإضافات بعد اسم الملف.

> إذا المحرر صار يشتغل بهالطريقة بس الـ F5 بعده أسود: من المحرر روح Project ← Project Settings ← فعّل
> **Advanced Settings** ← Rendering ← Rendering Device ← وغيّر **Driver.windows** لـ `d3d12` أو `vulkan`
> (حسب الي اشتغل وياك). **لا تسوّي commit لهذا التغيير** إلا إذا تريده لكل الحاسبات.

### د) اقرا الخطأ الحقيقي
شغّل نسخة الـ **console** حتى تشوف شنو يصير:

```powershell
.\Godot_v4.7.2-stable_win64_console.exe --verbose --path "D:\games\dev\Brawlly"
```

ابحث عن أسطر بيها `ERROR` أو `Vulkan` أو `D3D12` أو `Failed to create`. وهم اللعبة تكتب سجل هنا:

```
%APPDATA%\Godot\app_userdata\Brawlly\logs\godot.log
```

(الصق المسار بشريط عنوان File Explorer.) دزّ هالملف إذا المشكلة بعدها، منه نعرف السبب بالضبط.

### هـ) امسح الكاش وخليه يستورد من جديد
سد Godot ← امسح مجلد **`.godot`** داخل المشروع (مخفي؛ فعّل Hidden items بـ File Explorer) ← افتح المشروع
مرة ثانية وانتظر الاستيراد يخلص. هذا يحل الحالة إذا انقطع الاستيراد الأول بالنص.

### و) تأكد من كارت الشاشة
اكتب `dxdiag` بـ Start ← تبويب **Display**: إذا **Feature Levels** ما بيها `12_0` و **Driver Model** أقدم
من WDDM 2.0، فالكارت قديم على Vulkan / D3D12، واستخدم الحل الثالث من (ج) (OpenGL).

---

## 4. إذا تشغّل `Brawlly.exe` المصدَّرة (مو المشروع)

- لازم يكون **`Brawlly.exe` و `Brawlly.pck` بنفس المجلد**: الـ pck مو مدموج بالـ exe، وبدونه اللعبة ما تشتغل.
  انسخ المجلد كامل، مو الـ exe بس.
- نفس حلول الشاشة السودة تشتغل وياها: `Brawlly.exe --rendering-driver d3d12` أو
  `Brawlly.exe --rendering-method gl_compatibility --rendering-driver opengl3`.
- الحاسبة الي تلعب ما تحتاج Godot، بس تحتاج درايفر كارت شاشة محدّث.

---

## 5. اللعب أونلاين بين حاسبتين (شبكة البيت)

- اللعبة تستخدم **UDP 24565** للعب و **UDP 24566** حتى تلكى الألعاب بـ Find Game.
- أول مرة تشتغل، Windows يسأل عن الـ Firewall: اختار **Private networks** ← Allow.
  إذا Find Game ما يلكى اللعبة: Windows Security ← Firewall ← Allow an app ← فعّل Godot / Brawlly على Private.
- لازم الحاسبتين على **نفس نسخة الكود**: نسخة أقدم ما تشوف اللعبة بالقائمة (`Net.GAME_ID` مختلف).

---

## باختصار

1. Godot **4.7.2** Standard (+ نسخة console).
2. **درايفر كارت الشاشة** من موقع الشركة ← Restart.
3. أول فتح: انتظر الاستيراد يخلص.
4. بعدها أسود؟ ← `--rendering-driver d3d12` ← بعدها أسود؟ ← `--rendering-method gl_compatibility --rendering-driver opengl3`.
5. بعدها أسود؟ ← دزّ `godot.log`.
