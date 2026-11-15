//! Короткая команда `сфера` — единая точка входа в инструменты языка.
//!
//!   сфера установить математика    установить пакет из каталога (как pip/npm install)
//!   сфера установить               поставить всё из сфера.зависимости
//!   сфера войти / опубликовать     опубликовать свой пакет в реестр
//!   сфера искать ТЕКСТ             поиск по каталогу пакетов
//!   сфера добавить ИМЯ | удалить ИМЯ | список | индекс-настроить | индекс-обновить
//!   сфера запустить файл.код       собрать и запустить программу (то же, что `запустить`)
//!
//! Это тонкая обёртка: она запускает соседние программы `сфера_пакеты` и `запустить`
//! (лежат в той же папке, что и она сама, либо в PATH) и возвращает их код выхода.

use std::path::PathBuf;
use std::process::{exit, Command};

fn соседняя_программа(имя: &str) -> PathBuf {
    let с_расширением = if cfg!(windows) { format!("{}.exe", имя) } else { имя.to_string() };
    if let Ok(сама) = std::env::current_exe() {
        if let Some(папка) = сама.parent() {
            let путь = папка.join(&с_расширением);
            if путь.exists() {
                return путь;
            }
        }
    }
    PathBuf::from(с_расширением)
}

fn запустить_и_выйти(программа: &str, аргументы: &[String]) -> ! {
    match Command::new(соседняя_программа(программа)).args(аргументы).status() {
        Ok(статус) => exit(статус.code().unwrap_or(1)),
        Err(e) => {
            eprintln!("Ошибка: не удалось запустить '{}': {}. Установлена ли Сфера полностью?", программа, e);
            exit(1);
        }
    }
}

fn домашняя_папка() -> PathBuf {
    PathBuf::from(std::env::var("HOME").or_else(|_| std::env::var("USERPROFILE")).unwrap_or_else(|_| ".".to_string()))
}

fn ошибка(текст: &str) -> ! {
    eprintln!("Ошибка: {}", текст);
    exit(1);
}

fn выполнить(команда: &mut Command, что: &str) {
    match команда.status() {
        Ok(с) if с.success() => {}
        Ok(с) => ошибка(&format!("{} завершилось с кодом {}", что, с.code().unwrap_or(-1))),
        Err(е) => ошибка(&format!("не удалось запустить {}: {}", что, е)),
    }
}

/// `сфера собрать-android программа.код` — компилирует программу под Android (arm64) и упаковывает
/// её в готовое подписанное приложение: нужен Android NDK и шаблон приложения (Sfera-App-Template.apk).
fn собрать_android(аргументы: &[String]) -> ! {
    let mut файл: Option<String> = None;
    let (mut имя, mut выход, mut пакет, mut ndk, mut шаблон) = (None, None, None, None, None);
    let mut и = 0;
    while и < аргументы.len() {
        let значение = |и: usize| аргументы.get(и + 1).cloned().unwrap_or_else(|| ошибка(&format!("после {} нужно значение", аргументы[и])));
        match аргументы[и].as_str() {
            "--имя" => { имя = Some(значение(и)); и += 2; }
            "--выход" => { выход = Some(значение(и)); и += 2; }
            "--пакет" => { пакет = Some(значение(и)); и += 2; }
            "--ndk" => { ndk = Some(значение(и)); и += 2; }
            "--шаблон" => { шаблон = Some(значение(и)); и += 2; }
            другое if другое.starts_with("--") => ошибка(&format!("неизвестный параметр '{}'", другое)),
            другое => {
                if файл.is_some() { ошибка("нужен один файл программы"); }
                файл = Some(другое.to_string());
                и += 1;
            }
        }
    }
    let файл = PathBuf::from(файл.unwrap_or_else(|| ошибка("укажите файл программы: сфера собрать-android файл.код")));
    if !файл.exists() { ошибка(&format!("нет файла {}", файл.display())); }
    let файл = файл.canonicalize().unwrap_or(файл);
    let заготовка = файл.file_stem().map(|с| с.to_string_lossy().to_string()).unwrap_or_else(|| "программа".to_string());
    let имя = имя.unwrap_or_else(|| заготовка.clone());
    let выход = PathBuf::from(выход.unwrap_or_else(|| format!("{}.apk", заготовка)));

    // Шаблон: параметр, переменная SFERA_ANDROID_ШАБЛОН, ~/.sfera/android/, рядом с программой.
    let mut кандидаты: Vec<PathBuf> = Vec::new();
    if let Some(ш) = шаблон { кандидаты.push(PathBuf::from(ш)); }
    if let Ok(ш) = std::env::var("SFERA_ANDROID_ШАБЛОН") { кандидаты.push(PathBuf::from(ш)); }
    кандидаты.push(домашняя_папка().join(".sfera").join("android").join("Sfera-App-Template.apk"));
    if let Ok(сама) = std::env::current_exe() {
        if let Some(п) = сама.parent() { кандидаты.push(п.join("Sfera-App-Template.apk")); }
    }
    let шаблон = кандидаты.iter().find(|к| к.exists()).cloned().unwrap_or_else(|| {
        ошибка("не найден шаблон приложения Sfera-App-Template.apk (скачайте его со страницы «Скачать» на сайте и положите в ~/.sfera/android/ или укажите --шаблон)")
    });

    // NDK: параметр или ANDROID_NDK / ANDROID_NDK_HOME.
    let ndk = ndk.or_else(|| std::env::var("ANDROID_NDK").ok()).or_else(|| std::env::var("ANDROID_NDK_HOME").ok())
        .unwrap_or_else(|| ошибка("не найден Android NDK: укажите --ndk ПАПКА или задайте ANDROID_NDK"));
    let хост = if cfg!(target_os = "macos") { "darwin-x86_64" } else if cfg!(windows) { "windows-x86_64" } else { "linux-x86_64" };
    let инструменты = PathBuf::from(&ndk).join("toolchains").join("llvm").join("prebuilt").join(хост);
    let sysroot = инструменты.join("sysroot");
    if !sysroot.exists() { ошибка(&format!("в NDK нет {} — неверный путь к NDK?", sysroot.display())); }

    let временная = std::env::temp_dir().join(format!("sfera-android-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&временная);
    let библиотеки = временная.join("lib");
    let _ = std::fs::create_dir_all(&библиотеки);

    println!("1/3  Достаю библиотеки SDL из шаблона...");
    выполнить(Command::new(соседняя_программа("сфера_apk")).arg("извлечь-библиотеки").arg(&шаблон).arg(&библиотеки), "сфера_apk");

    println!("2/3  Компилирую программу под Android (arm64)...");
    let путь = {
        let mut части = vec![инструменты.join("bin")];
        части.extend(std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()));
        std::env::join_paths(части).unwrap_or_default()
    };
    let папка_программы = файл.parent().map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."));
    выполнить(
        Command::new(соседняя_программа("запустить"))
            .current_dir(&папка_программы)
            .env("PATH", путь)
            .env("SFERA_ANDROID_LIBDIR", &библиотеки)
            .arg(&файл).arg("--только-собрать")
            .args(["--целевая-платформа", "aarch64-linux-android21", "--android-sysroot"]).arg(&sysroot)
            .args(["--android-so", "--линковать", "SDL2", "--линковать", "SDL2_ttf"]),
        "компилятор",
    );
    let собранный = папка_программы.join(&заготовка);
    if !собранный.exists() { ошибка(&format!("компилятор не создал {}", собранный.display())); }
    let so = временная.join("libmain.so");
    if let Err(е) = std::fs::copy(&собранный, &so) { ошибка(&format!("не удалось скопировать результат: {}", е)); }
    let _ = std::fs::remove_file(&собранный);

    println!("3/3  Упаковываю и подписываю...");
    let mut упаковка = Command::new(соседняя_программа("сфера_apk"));
    упаковка.arg("упаковать").arg("--шаблон").arg(&шаблон).arg("--библиотека").arg(&so)
        .arg("--имя").arg(&имя).arg("--выход").arg(&выход);
    if let Some(п) = пакет { упаковка.arg("--пакет").arg(п); }
    выполнить(&mut упаковка, "сфера_apk");
    let _ = std::fs::remove_dir_all(&временная);
    println!("Готово. Скопируйте {} на телефон и установите (разрешите установку из неизвестных источников).", выход.display());
    exit(0);
}

fn справка() {
    println!("сфера — инструменты языка «Сфера»");
    println!();
    println!("Пакеты:");
    println!("  сфера установить ИМЯ[@ВЕРСИЯ]   поставить пакет(ы) из реестра или каталога");
    println!("  сфера установить                поставить всё из сфера.зависимости");
    println!("  сфера искать ТЕКСТ              найти пакет в каталоге");
    println!("  сфера добавить ИМЯ              дописать пакет в сфера.зависимости");
    println!("  сфера удалить ИМЯ [--force]     убрать пакет");
    println!("  сфера список                    показать установленные пакеты");
    println!("  сфера индекс-настроить URL      сменить каталог пакетов");
    println!("  сфера индекс-обновить           обновить копию каталога");
    println!("  сфера новый-пакет ИМЯ           создать папку-заготовку своего пакета");
    println!("  сфера войти [ТОКЕН]             запомнить токен автора");
    println!("  сфера опубликовать              отправить пакет из текущей папки в реестр");
    println!("  сфера выйти                     забыть токен автора");
    println!();
    println!("Программы:");
    println!("  сфера запустить файл.код        собрать и запустить (все параметры как у `запустить`)");
    println!("  сфера собрать-android файл.код  упаковать программу в приложение для Android (.apk)");
    println!("        [--имя \"Название\"] [--выход файл.apk] [--пакет ru.sfera.app.имя] [--ndk ПАПКА] [--шаблон Sfera-App-Template.apk]");
    println!();
    println!("Каталог пакетов: https://языксфера.рф/пакеты");
}

fn main() {
    let аргументы: Vec<String> = std::env::args().skip(1).collect();
    let команда = аргументы.first().map(String::as_str).unwrap_or("");
    match команда {
        "" | "помощь" | "--помощь" | "-h" | "--help" => справка(),
        "установить" | "искать" | "каталог" | "добавить" | "удалить" | "список" | "индекс-настроить" | "индекс-обновить" | "войти"
        | "выйти" | "опубликовать" | "новый-пакет" => {
            запустить_и_выйти("сфера_пакеты", &аргументы)
        }
        "запустить" => запустить_и_выйти("запустить", &аргументы[1..]),
        "собрать-android" => собрать_android(&аргументы[1..]),
        другое => {
            eprintln!("Неизвестная команда '{}'. Список команд: сфера помощь", другое);
            exit(1);
        }
    }
}
