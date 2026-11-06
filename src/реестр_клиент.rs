//! Клиентская часть хранилища пакетов: реестр на сайте языка.
//!
//! Подключается к `сфера_пакеты` как модуль. Здесь: SHA-256 (без внешних библиотек), загрузка
//! списка версий, скачивание и проверка архива, упаковка и публикация, хранение токена автора.
//!
//! Формат пакета: архив .tar.gz, в корне только файлы (*.код, *.md, LICENSE, сфера.зависимости)
//! и манифест `пакет.сфера` («ключ = значение»: имя, версия, описание, лицензия).

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::OnceLock;

/// Адрес раздела пакетов на сайте (латинская запись домена, чтобы curl не спотыкался об IDN).
/// Для проверок и своих серверов заменяется переменной окружения SFERA_REGISTRY.
const АДРЕС_ПО_УМОЛЧАНИЮ: &str = "https://xn--80ajfm5aev7c8a.xn--p1ai/%D0%BF%D0%B0%D0%BA%D0%B5%D1%82%D1%8B";

pub const ИМЯ_РЕЕСТРА: &str = "реестр";

pub fn адрес_реестра() -> String {
    std::env::var("SFERA_REGISTRY")
        .ok()
        .map(|s| s.trim().trim_end_matches('/').to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| АДРЕС_ПО_УМОЛЧАНИЮ.to_string())
}

// ---------------------------------------------------------------- SHA-256

pub fn sha256_hex(данные: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    let mut сообщение = данные.to_vec();
    сообщение.push(0x80);
    while сообщение.len() % 64 != 56 {
        сообщение.push(0);
    }
    сообщение.extend_from_slice(&((данные.len() as u64) * 8).to_be_bytes());
    for блок in сообщение.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([блок[i * 4], блок[i * 4 + 1], блок[i * 4 + 2], блок[i * 4 + 3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ (!e & g);
            let t1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let мажор = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(мажор);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        for (x, y) in h.iter_mut().zip([a, b, c, d, e, f, g, hh]) {
            *x = x.wrapping_add(y);
        }
    }
    h.iter().map(|x| format!("{:08x}", x)).collect()
}

// ---------------------------------------------------------------- адреса и токен

/// Процентное кодирование для частей адреса (имя пакета может быть русским).
pub fn закодировать(текст: &str) -> String {
    let mut итог = String::new();
    for байт in текст.bytes() {
        match байт {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => итог.push(байт as char),
            _ => итог.push_str(&format!("%{:02X}", байт)),
        }
    }
    итог
}

fn адрес_раздела(часть: &str) -> String {
    format!("{}/{}", адрес_реестра(), часть)
}

fn папка_настроек() -> Result<PathBuf, String> {
    let дом = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .map_err(|_| "не удалось определить домашнюю папку (нет ни HOME, ни USERPROFILE)".to_string())?;
    Ok(PathBuf::from(дом).join(".сфера"))
}

fn путь_токена() -> Result<PathBuf, String> {
    Ok(папка_настроек()?.join("токен.txt"))
}

/// Токен автора: переменная SFERA_TOKEN (удобно для автоматических сборок) или файл ~/.сфера/токен.txt.
pub fn прочитать_токен() -> Option<String> {
    if let Ok(токен) = std::env::var("SFERA_TOKEN") {
        let токен = токен.trim().to_string();
        if !токен.is_empty() {
            return Some(токен);
        }
    }
    fs::read_to_string(путь_токена().ok()?).ok().map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
}

/// «сфера войти [ТОКЕН]»: запоминает токен автора на этой машине.
pub fn войти(токен: Option<&str>) -> Result<(), String> {
    let токен = match токен {
        Some(т) => т.trim().to_string(),
        None => {
            eprint!("Вставьте токен автора (его выдаёт администратор сайта): ");
            std::io::stderr().flush().ok();
            let mut строка = String::new();
            std::io::stdin().read_line(&mut строка).map_err(|e| format!("не удалось прочитать токен: {}", e))?;
            строка.trim().to_string()
        }
    };
    if токен.len() < 30 || !токен.bytes().all(|б| б.is_ascii_alphanumeric()) {
        return Err("токен выглядит неверно: ожидается 40 латинских букв и цифр без пробелов".to_string());
    }
    let папка = папка_настроек()?;
    fs::create_dir_all(&папка).map_err(|e| format!("не удалось создать '{}': {}", папка.display(), e))?;
    let путь = путь_токена()?;
    fs::write(&путь, format!("{}\n", токен)).map_err(|e| format!("не удалось сохранить токен: {}", e))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&путь, fs::Permissions::from_mode(0o600)).ok();
    }
    println!("Токен сохранён в {}. Теперь можно публиковать: сфера опубликовать", путь.display());
    Ok(())
}

pub fn выйти() -> Result<(), String> {
    let путь = путь_токена()?;
    if путь.exists() {
        fs::remove_file(&путь).map_err(|e| format!("не удалось удалить токен: {}", e))?;
        println!("Токен удалён.");
    } else {
        println!("Токен не был сохранён.");
    }
    Ok(())
}

// ---------------------------------------------------------------- реестр версий

#[derive(Clone, Debug)]
pub struct ЗаписьРеестра {
    pub имя: String,
    pub версия: String,
    pub сумма: String,
    pub автор: String,
    pub описание: String,
    pub отозвана: bool,
}

fn разобрать_реестр(текст: &str) -> Vec<ЗаписьРеестра> {
    let mut записи = Vec::new();
    for строка in текст.lines() {
        let строка = строка.trim();
        if строка.is_empty() || строка.starts_with('#') {
            continue;
        }
        let поля: Vec<&str> = строка.split('|').map(str::trim).collect();
        if поля.len() < 8 {
            continue;
        }
        записи.push(ЗаписьРеестра {
            имя: поля[0].to_string(),
            версия: поля[1].to_string(),
            сумма: поля[2].to_string(),
            автор: поля[5].to_string(),
            описание: поля[6].to_string(),
            отозвана: поля[7] == "1",
        });
    }
    записи
}

fn скачать_текст(адрес: &str) -> Result<String, String> {
    let вывод = Command::new("curl")
        .args(["-fsSL", "--max-time", "30", "--max-filesize", "5000000", адрес])
        .output()
        .map_err(|e| format!("не удалось запустить curl (установлен ли он?): {}", e))?;
    if !вывод.status.success() {
        return Err(format!("не удалось загрузить {}: {}", адрес, String::from_utf8_lossy(&вывод.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&вывод.stdout).to_string())
}

static РЕЕСТР: OnceLock<Result<Vec<ЗаписьРеестра>, String>> = OnceLock::new();

/// Весь реестр (один запрос за запуск программы).
pub fn загрузить_реестр() -> Result<Vec<ЗаписьРеестра>, String> {
    РЕЕСТР
        .get_or_init(|| {
            let текст = скачать_текст(&адрес_раздела(&закодировать("реестр.txt")))?;
            Ok(разобрать_реестр(&текст))
        })
        .clone()
}

/// Все версии пакета (включая отозванные).
pub fn версии_пакета(имя: &str) -> Result<Vec<ЗаписьРеестра>, String> {
    Ok(загрузить_реестр()?.into_iter().filter(|з| з.имя == имя).collect())
}

fn разобрать_x_y_z(версия: &str) -> (u64, u64, u64) {
    let части: Vec<u64> = версия.split('.').map(|ч| ч.parse().unwrap_or(0)).collect();
    (*части.first().unwrap_or(&0), *части.get(1).unwrap_or(&0), *части.get(2).unwrap_or(&0))
}

/// Самая новая не отозванная версия.
pub fn последняя_версия(имя: &str) -> Result<Option<ЗаписьРеестра>, String> {
    let mut версии: Vec<ЗаписьРеестра> = версии_пакета(имя)?.into_iter().filter(|з| !з.отозвана).collect();
    версии.sort_by_key(|з| разобрать_x_y_z(&з.версия));
    Ok(версии.pop())
}

/// Поиск по имени и описанию: по одной (последней) записи на пакет.
pub fn искать(запрос: &str) -> Result<Vec<ЗаписьРеестра>, String> {
    let запрос = запрос.to_lowercase();
    let mut имена: Vec<String> = Vec::new();
    for з in загрузить_реестр()? {
        if !имена.contains(&з.имя)
            && (з.имя.to_lowercase().contains(&запрос) || з.описание.to_lowercase().contains(&запрос))
        {
            имена.push(з.имя.clone());
        }
    }
    let mut итог = Vec::new();
    for имя in имена {
        if let Some(з) = последняя_версия(&имя)? {
            итог.push(з);
        }
    }
    Ok(итог)
}

// ---------------------------------------------------------------- работа с архивами

/// Список имён в архиве. GNU tar по умолчанию экранирует не-ASCII имена, поэтому просим «как есть».
fn имена_в_архиве(архив: &Path) -> Result<Vec<String>, String> {
    let mut вывод = Command::new("tar").arg("--quoting-style=literal").arg("-tzf").arg(архив).output();
    if !matches!(&вывод, Ok(в) if в.status.success()) {
        // bsdtar (macOS, Windows) такой опции не знает и не экранирует.
        вывод = Command::new("tar").arg("-tzf").arg(архив).output();
    }
    let вывод = вывод.map_err(|e| format!("не удалось запустить tar: {}", e))?;
    if !вывод.status.success() {
        return Err("архив повреждён или это не .tar.gz".to_string());
    }
    Ok(String::from_utf8_lossy(&вывод.stdout).lines().map(str::to_string).filter(|с| !с.is_empty()).collect())
}

/// Скачивает архив версии, сверяет SHA-256 с реестром (и с блокировкой, если она есть) и
/// распаковывает в `назначение` (папка должна существовать и быть пустой). Возвращает контрольную сумму.
pub fn установить_из_реестра(
    имя: &str,
    версия: &str,
    ожидаемая_по_блокировке: Option<&str>,
    назначение: &Path,
) -> Result<String, String> {
    let запись = версии_пакета(имя)?
        .into_iter()
        .find(|з| з.версия == версия)
        .ok_or_else(|| format!("в реестре нет пакета '{}' версии {}", имя, версия))?;

    let временный = std::env::temp_dir().join(format!("сфера_реестр_{}_{}.tar.gz", std::process::id(), закодировать(имя)));
    let адрес = адрес_архива(имя, версия);
    let вывод = Command::new("curl")
        .args(["-fsSL", "--max-time", "120", "--max-filesize", "6000000", "-o"])
        .arg(&временный)
        .arg(&адрес)
        .output()
        .map_err(|e| format!("не удалось запустить curl (установлен ли он?): {}", e))?;
    if !вывод.status.success() {
        fs::remove_file(&временный).ok();
        return Err(format!("не удалось скачать '{}' {}: {}", имя, версия, String::from_utf8_lossy(&вывод.stderr).trim()));
    }
    let результат = (|| -> Result<String, String> {
        let байты = fs::read(&временный).map_err(|e| format!("не удалось прочитать скачанный архив: {}", e))?;
        let сумма = sha256_hex(&байты);
        if сумма != запись.сумма {
            return Err(format!(
                "контрольная сумма '{}' {} не совпала с реестром (ожидалась {}, получена {}) — архив повреждён по пути, установка отменена",
                имя, версия, запись.сумма, сумма
            ));
        }
        if let Some(в_блокировке) = ожидаемая_по_блокировке {
            if в_блокировке != сумма {
                return Err(format!(
                    "'{}' {}: содержимое пакета отличается от записанного в 'сфера.блокировка' (там {}, сейчас {}). \
                     Версии в реестре неизменны, так что это подмена или ошибка. Если уверены, что так и надо, \
                     выполните 'установить --обновить-блокировку'.",
                    имя, версия, в_блокировке, сумма
                ));
            }
        }
        for файл in имена_в_архиве(&временный)? {
            if файл.starts_with('/') || файл.starts_with('.') || файл.contains('/') || файл.contains('\\') || файл.contains("..") {
                return Err(format!("в архиве '{}' недопустимый путь '{}' — установка отменена", имя, файл));
            }
        }
        let вывод = Command::new("tar")
            .arg("-xzf")
            .arg(&временный)
            .arg("-C")
            .arg(назначение)
            .output()
            .map_err(|e| format!("не удалось запустить tar: {}", e))?;
        if !вывод.status.success() {
            return Err(format!("не удалось распаковать архив: {}", String::from_utf8_lossy(&вывод.stderr).trim()));
        }
        Ok(сумма)
    })();
    fs::remove_file(&временный).ok();
    результат
}

fn адрес_архива(имя: &str, версия: &str) -> String {
    адрес_части(&format!("{}/{}/{}.tar.gz", закодировать("архив"), закодировать(имя), версия))
}

fn адрес_части(часть: &str) -> String {
    format!("{}/{}", адрес_реестра(), часть)
}

// ---------------------------------------------------------------- публикация

pub struct Манифест {
    pub имя: String,
    pub версия: String,
    pub описание: String,
}

fn поле(манифест: &str, ключ: &str) -> String {
    for строка in манифест.lines() {
        if let Some((к, з)) = строка.split_once('=') {
            if к.trim() == ключ {
                return з.trim().to_string();
            }
        }
    }
    String::new()
}

pub fn прочитать_манифест(папка: &Path) -> Result<Манифест, String> {
    let путь = папка.join("пакет.сфера");
    let текст = fs::read_to_string(&путь).map_err(|_| {
        "в текущей папке нет файла 'пакет.сфера'. Создайте его, например:\n\n  имя = математика\n  версия = 1.0.0\n  описание = Функции корня и степени\n  лицензия = MIT\n"
            .to_string()
    })?;
    let м = Манифест { имя: поле(&текст, "имя"), версия: поле(&текст, "версия"), описание: поле(&текст, "описание") };
    if м.имя.is_empty() || м.версия.is_empty() || м.описание.is_empty() {
        return Err("в 'пакет.сфера' нужны поля: имя, версия, описание".to_string());
    }
    let части: Vec<&str> = м.версия.split('.').collect();
    if части.len() != 3 || части.iter().any(|ч| ч.is_empty() || !ч.bytes().all(|б| б.is_ascii_digit())) {
        return Err(format!("версия '{}' должна быть вида X.Y.Z, например 1.0.0", м.версия));
    }
    Ok(м)
}

fn файл_входит_в_пакет(имя: &str) -> bool {
    имя == "пакет.сфера" || имя == "сфера.зависимости" || имя == "LICENSE" || имя.ends_with(".код") || имя.ends_with(".md")
}

/// «сфера опубликовать»: упаковывает текущую папку и отправляет в реестр.
pub fn опубликовать() -> Result<(), String> {
    let токен = прочитать_токен().ok_or_else(|| "нужен токен автора: сначала выполните 'сфера войти'".to_string())?;
    let папка = Path::new(".");
    let м = прочитать_манифест(папка)?;

    let mut файлы: Vec<String> = Vec::new();
    for запись in fs::read_dir(папка).map_err(|e| format!("не удалось прочитать папку: {}", e))? {
        let запись = запись.map_err(|e| e.to_string())?;
        if !запись.file_type().map(|т| т.is_file()).unwrap_or(false) {
            continue;
        }
        let имя = запись.file_name().to_string_lossy().to_string();
        if файл_входит_в_пакет(&имя) && !имя.starts_with('.') {
            файлы.push(имя);
        }
    }
    файлы.sort();
    if !файлы.iter().any(|ф| ф.ends_with(".код")) {
        return Err("в текущей папке нет ни одного файла .код".to_string());
    }

    let архив = std::env::temp_dir().join(format!("сфера_публикация_{}.tar.gz", std::process::id()));
    let вывод = Command::new("tar")
        .env("COPYFILE_DISABLE", "1")
        .arg("-czf")
        .arg(&архив)
        .args(&файлы)
        .output()
        .map_err(|e| format!("не удалось запустить tar: {}", e))?;
    if !вывод.status.success() {
        return Err(format!("не удалось создать архив: {}", String::from_utf8_lossy(&вывод.stderr).trim()));
    }
    let результат = (|| -> Result<(), String> {
        let размер = fs::metadata(&архив).map(|м| м.len()).unwrap_or(0);
        if размер > 5_000_000 {
            return Err(format!("архив {} КБ — больше лимита 5 МБ", размер / 1024));
        }
        println!("Публикую {} {} ({} КБ, файлов: {}):", м.имя, м.версия, (размер + 1023) / 1024, файлы.len());
        for ф in &файлы {
            println!("  {}", ф);
        }
        let адрес = адрес_части(&format!("{}/{}/{}", закодировать("публикация"), закодировать(&м.имя), м.версия));
        // Токен передаётся через стандартный ввод curl, а не аргументом: так он не виден в списке процессов.
        let mut curl = Command::new("curl")
            .args(["-sS", "--max-time", "120", "-X", "PUT", "-K", "-", "-T"])
            .arg(&архив)
            .args(["-w", "\n%{http_code}"])
            .arg(&адрес)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("не удалось запустить curl (установлен ли он?): {}", e))?;
        curl.stdin
            .take()
            .ok_or("не удалось передать токен curl")?
            .write_all(format!("header = \"Authorization: Bearer {}\"\n", токен).as_bytes())
            .map_err(|e| format!("не удалось передать токен curl: {}", e))?;
        let вывод = curl.wait_with_output().map_err(|e| format!("curl завершился с ошибкой: {}", e))?;
        if !вывод.status.success() {
            return Err(format!("не удалось связаться с реестром: {}", String::from_utf8_lossy(&вывод.stderr).trim()));
        }
        let ответ = String::from_utf8_lossy(&вывод.stdout).to_string();
        let (тело, код) = ответ.rsplit_once('\n').unwrap_or((&ответ, ""));
        if код.trim() == "201" {
            println!("\nГотово: {} {} опубликован.", м.имя, м.версия);
            println!("Установка: сфера установить {}", м.имя);
            return Ok(());
        }
        let сообщение = тело
            .split("\"ошибка\":\"")
            .nth(1)
            .and_then(|с| с.split('"').next())
            .unwrap_or(тело.trim());
        Err(format!("реестр отклонил публикацию ({}): {}", код.trim(), сообщение.replace("\\\"", "\"")))
    })();
    fs::remove_file(&архив).ok();
    результат
}

#[cfg(test)]
mod тесты {
    use super::*;

    #[test]
    fn sha256_известные_значения() {
        assert_eq!(sha256_hex(b""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        assert_eq!(sha256_hex(b"abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        let длинный = vec![b'a'; 1000];
        assert_eq!(sha256_hex(&длинный), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3");
    }

    #[test]
    fn кодирование_адреса() {
        assert_eq!(закодировать("пакет-1.0"), "%D0%BF%D0%B0%D0%BA%D0%B5%D1%82-1.0");
    }
}
