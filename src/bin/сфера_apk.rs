//! сфера_apk — упаковывает программу Сферы в готовый к установке Android-приложение (.apk).
//!
//! Как это работает: берётся «шаблон» — APK с окном SDL, библиотеками SDL2 и шрифтами (его собирает
//! собрать-apk.sh, он же лежит внутри панели Android), в него подставляется собранная программа
//! (`lib/arm64-v8a/libmain.so`), меняются имя и идентификатор приложения в манифесте, и всё
//! подписывается. Ни Android SDK, ни Java для этого не нужны — инструмент работает и на компьютере,
//! и на самом телефоне (внутри панели).
//!
//!   сфера_apk упаковать --шаблон шаблон.apk --библиотека libmain.so --имя "Моя игра" --выход игра.apk
//!                       [--пакет ru.sfera.moя_игра] [--ключ путь/к/ключу.txt]
//!   сфера_apk ключ [путь]      создаёт ключ подписи (если его ещё нет) и печатает отпечаток
//!
//! Подпись — схема v1 (JAR), ключ ECDSA P-256 создаётся один раз и хранится в файле: приложения,
//! подписанные одним ключом, ставятся поверх старых версий. Подходит для приложений с
//! targetSdkVersion ≤ 29 (шаблон Сферы использует 28).

use flate2::read::DeflateDecoder;
use flate2::write::DeflateEncoder;
use flate2::{Compression, Crc};
use p256::ecdsa::{signature::Signer, Signature, SigningKey};
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

// ───────────────────────────── ZIP ─────────────────────────────

/// Одна запись архива. Данные хранятся «как есть» (уже сжатые), поэтому записи шаблона
/// копируются без перепаковки.
#[derive(Clone)]
struct Запись {
    имя: String,
    метод: u16,
    crc: u32,
    размер: u32,
    данные: Vec<u8>,
}

fn u16_из(б: &[u8], п: usize) -> Result<u16, String> {
    б.get(п..п + 2).map(|x| u16::from_le_bytes([x[0], x[1]])).ok_or_else(|| "архив обрезан".to_string())
}

fn u32_из(б: &[u8], п: usize) -> Result<u32, String> {
    б.get(п..п + 4).map(|x| u32::from_le_bytes([x[0], x[1], x[2], x[3]])).ok_or_else(|| "архив обрезан".to_string())
}

fn прочитать_zip(байты: &[u8]) -> Result<Vec<Запись>, String> {
    // Конец центрального каталога ищем с конца файла.
    if байты.len() < 22 {
        return Err("это не zip-архив".to_string());
    }
    let mut eocd = None;
    let начало_поиска = байты.len().saturating_sub(22 + 65535);
    let mut п = байты.len() - 22;
    loop {
        if u32_из(байты, п)? == 0x0605_4b50 {
            eocd = Some(п);
            break;
        }
        if п == начало_поиска {
            break;
        }
        п -= 1;
    }
    let eocd = eocd.ok_or("это не zip-архив (нет конца каталога)")?;
    let число = u16_из(байты, eocd + 10)? as usize;
    let смещение_каталога = u32_из(байты, eocd + 16)? as usize;
    if число == 0xFFFF || смещение_каталога == 0xFFFF_FFFF {
        return Err("zip64 не поддерживается".to_string());
    }
    let mut записи = Vec::new();
    let mut п = смещение_каталога;
    for _ in 0..число {
        if u32_из(байты, п)? != 0x0201_4b50 {
            return Err("повреждён центральный каталог архива".to_string());
        }
        let метод = u16_из(байты, п + 10)?;
        let crc = u32_из(байты, п + 16)?;
        let сжатый = u32_из(байты, п + 20)? as usize;
        let размер = u32_из(байты, п + 24)?;
        let длина_имени = u16_из(байты, п + 28)? as usize;
        let длина_доп = u16_из(байты, п + 30)? as usize;
        let длина_коммент = u16_из(байты, п + 32)? as usize;
        let смещение_локального = u32_из(байты, п + 42)? as usize;
        let имя = String::from_utf8_lossy(байты.get(п + 46..п + 46 + длина_имени).ok_or("архив обрезан")?).to_string();
        // Локальный заголовок: у него свои длины имени и «дополнительных» данных.
        if u32_из(байты, смещение_локального)? != 0x0403_4b50 {
            return Err("повреждён локальный заголовок архива".to_string());
        }
        let л_имя = u16_из(байты, смещение_локального + 26)? as usize;
        let л_доп = u16_из(байты, смещение_локального + 28)? as usize;
        let начало = смещение_локального + 30 + л_имя + л_доп;
        let данные = байты.get(начало..начало + сжатый).ok_or("архив обрезан")?.to_vec();
        записи.push(Запись { имя, метод, crc, размер, данные });
        п += 46 + длина_имени + длина_доп + длина_коммент;
    }
    Ok(записи)
}

fn содержимое(з: &Запись) -> Result<Vec<u8>, String> {
    match з.метод {
        0 => Ok(з.данные.clone()),
        8 => {
            let mut выход = Vec::with_capacity(з.размер as usize);
            DeflateDecoder::new(&з.данные[..])
                .read_to_end(&mut выход)
                .map_err(|e| format!("не удалось распаковать '{}': {}", з.имя, e))?;
            Ok(выход)
        }
        м => Err(format!("запись '{}' сжата неподдерживаемым методом {}", з.имя, м)),
    }
}

fn crc32(данные: &[u8]) -> u32 {
    let mut c = Crc::new();
    c.update(данные);
    c.sum()
}

fn запись_из_данных(имя: &str, данные: &[u8], сжимать: bool) -> Запись {
    let crc = crc32(данные);
    if сжимать && данные.len() > 64 {
        let mut е = DeflateEncoder::new(Vec::new(), Compression::new(6));
        е.write_all(данные).unwrap();
        let сжатое = е.finish().unwrap();
        if сжатое.len() < данные.len() {
            return Запись { имя: имя.to_string(), метод: 8, crc, размер: данные.len() as u32, данные: сжатое };
        }
    }
    Запись { имя: имя.to_string(), метод: 0, crc, размер: данные.len() as u32, данные: данные.to_vec() }
}

fn записать_zip(записи: &[Запись]) -> Vec<u8> {
    // Время 1 января 2020 — архив получается одинаковым при одинаковых входных данных.
    let (время, дата): (u16, u16) = (0, ((2020 - 1980) << 9) | (1 << 5) | 1);
    let mut выход: Vec<u8> = Vec::new();
    let mut смещения = Vec::new();
    for з in записи {
        смещения.push(выход.len() as u32);
        let флаги: u16 = if з.имя.is_ascii() { 0 } else { 0x0800 };
        выход.extend_from_slice(&0x0403_4b50u32.to_le_bytes());
        выход.extend_from_slice(&20u16.to_le_bytes());
        выход.extend_from_slice(&флаги.to_le_bytes());
        выход.extend_from_slice(&з.метод.to_le_bytes());
        выход.extend_from_slice(&время.to_le_bytes());
        выход.extend_from_slice(&дата.to_le_bytes());
        выход.extend_from_slice(&з.crc.to_le_bytes());
        выход.extend_from_slice(&(з.данные.len() as u32).to_le_bytes());
        выход.extend_from_slice(&з.размер.to_le_bytes());
        выход.extend_from_slice(&(з.имя.len() as u16).to_le_bytes());
        выход.extend_from_slice(&0u16.to_le_bytes());
        выход.extend_from_slice(з.имя.as_bytes());
        выход.extend_from_slice(&з.данные);
    }
    let начало_каталога = выход.len() as u32;
    for (з, смещение) in записи.iter().zip(&смещения) {
        let флаги: u16 = if з.имя.is_ascii() { 0 } else { 0x0800 };
        выход.extend_from_slice(&0x0201_4b50u32.to_le_bytes());
        выход.extend_from_slice(&0x0314u16.to_le_bytes()); // создано в Unix
        выход.extend_from_slice(&20u16.to_le_bytes());
        выход.extend_from_slice(&флаги.to_le_bytes());
        выход.extend_from_slice(&з.метод.to_le_bytes());
        выход.extend_from_slice(&время.to_le_bytes());
        выход.extend_from_slice(&дата.to_le_bytes());
        выход.extend_from_slice(&з.crc.to_le_bytes());
        выход.extend_from_slice(&(з.данные.len() as u32).to_le_bytes());
        выход.extend_from_slice(&з.размер.to_le_bytes());
        выход.extend_from_slice(&(з.имя.len() as u16).to_le_bytes());
        выход.extend_from_slice(&0u16.to_le_bytes());
        выход.extend_from_slice(&0u16.to_le_bytes());
        выход.extend_from_slice(&0u16.to_le_bytes());
        выход.extend_from_slice(&0u16.to_le_bytes());
        выход.extend_from_slice(&(0o100644u32 << 16).to_le_bytes());
        выход.extend_from_slice(&смещение.to_le_bytes());
        выход.extend_from_slice(з.имя.as_bytes());
    }
    let размер_каталога = выход.len() as u32 - начало_каталога;
    выход.extend_from_slice(&0x0605_4b50u32.to_le_bytes());
    выход.extend_from_slice(&0u16.to_le_bytes());
    выход.extend_from_slice(&0u16.to_le_bytes());
    выход.extend_from_slice(&(записи.len() as u16).to_le_bytes());
    выход.extend_from_slice(&(записи.len() as u16).to_le_bytes());
    выход.extend_from_slice(&размер_каталога.to_le_bytes());
    выход.extend_from_slice(&начало_каталога.to_le_bytes());
    выход.extend_from_slice(&0u16.to_le_bytes());
    выход
}

// ─────────────────── Двоичный манифест (AXML) ───────────────────

fn прочитать_строку_пула(пул: &[u8], позиция: usize, utf8: bool) -> Result<String, String> {
    let ош = || "повреждён пул строк манифеста".to_string();
    if utf8 {
        let mut п = позиция;
        // длина в символах (нужна только для пропуска), затем длина в байтах
        let a = *пул.get(п).ok_or_else(ош)? as usize;
        п += if a & 0x80 != 0 { 2 } else { 1 };
        let б = *пул.get(п).ok_or_else(ош)? as usize;
        let (байты, сдвиг) = if б & 0x80 != 0 { ((((б & 0x7f) << 8) | *пул.get(п + 1).ok_or_else(ош)? as usize), 2) } else { (б, 1) };
        п += сдвиг;
        let срез = пул.get(п..п + байты).ok_or_else(ош)?;
        Ok(String::from_utf8_lossy(срез).to_string())
    } else {
        let а = u16_из(пул, позиция)? as usize;
        let (длина, сдвиг) = if а & 0x8000 != 0 {
            ((((а & 0x7fff) << 16) | u16_из(пул, позиция + 2)? as usize), 4)
        } else {
            (а, 2)
        };
        let срез = пул.get(позиция + сдвиг..позиция + сдвиг + длина * 2).ok_or_else(ош)?;
        let юниты: Vec<u16> = срез.chunks(2).map(|x| u16::from_le_bytes([x[0], x[1]])).collect();
        Ok(String::from_utf16_lossy(&юниты))
    }
}

fn записать_строку_пула(с: &str, utf8: bool, выход: &mut Vec<u8>) -> Result<(), String> {
    if utf8 {
        let символов = с.encode_utf16().count();
        let байт = с.len();
        if символов > 0x7fff || байт > 0x7fff {
            return Err("слишком длинная строка для манифеста".to_string());
        }
        for знач in [символов, байт] {
            if знач > 0x7f {
                выход.push(((знач >> 8) as u8) | 0x80);
                выход.push((знач & 0xff) as u8);
            } else {
                выход.push(знач as u8);
            }
        }
        выход.extend_from_slice(с.as_bytes());
        выход.push(0);
    } else {
        let юниты: Vec<u16> = с.encode_utf16().collect();
        if юниты.len() > 0x7fff_ffff {
            return Err("слишком длинная строка для манифеста".to_string());
        }
        if юниты.len() > 0x7fff {
            выход.extend_from_slice(&(((юниты.len() >> 16) as u16) | 0x8000).to_le_bytes());
            выход.extend_from_slice(&((юниты.len() & 0xffff) as u16).to_le_bytes());
        } else {
            выход.extend_from_slice(&(юниты.len() as u16).to_le_bytes());
        }
        for ю in юниты {
            выход.extend_from_slice(&ю.to_le_bytes());
        }
        выход.extend_from_slice(&0u16.to_le_bytes());
    }
    Ok(())
}

/// Заменяет строки в пуле строк двоичного манифеста Android. Остальное содержимое файла (элементы,
/// атрибуты, ссылки на ресурсы) ссылается на строки по номеру, поэтому не меняется.
fn заменить_строки_манифеста(данные: &[u8], замены: &[(String, String)]) -> Result<Vec<u8>, String> {
    if u16_из(данные, 0)? != 0x0003 {
        return Err("AndroidManifest.xml в шаблоне не в двоичном формате".to_string());
    }
    let п = 8usize;
    if u16_из(данные, п)? != 0x0001 {
        return Err("в манифесте нет пула строк".to_string());
    }
    let размер_заголовка = u16_из(данные, п + 2)? as usize;
    let размер_пула = u32_из(данные, п + 4)? as usize;
    let число = u32_из(данные, п + 8)? as usize;
    let число_стилей = u32_из(данные, п + 12)? as usize;
    let флаги = u32_из(данные, п + 16)?;
    let начало_строк = u32_из(данные, п + 20)? as usize;
    if число_стилей != 0 {
        return Err("стили в пуле строк манифеста не поддерживаются".to_string());
    }
    let utf8 = флаги & 0x100 != 0;
    let пул = данные.get(п..п + размер_пула).ok_or("манифест обрезан")?;
    let mut строки = Vec::with_capacity(число);
    for и in 0..число {
        let смещение = u32_из(пул, размер_заголовка + 4 * и)? as usize;
        строки.push(прочитать_строку_пула(пул, начало_строк + смещение, utf8)?);
    }
    let mut изменено = false;
    for с in строки.iter_mut() {
        for (было, стало) in замены {
            if с == было {
                *с = стало.clone();
                изменено = true;
                break;
            }
        }
    }
    if !изменено {
        return Err(format!(
            "в манифесте шаблона нет ожидаемых строк ({}) — это не тот шаблон",
            замены.iter().map(|(а, _)| format!("'{}'", а)).collect::<Vec<_>>().join(", ")
        ));
    }
    // Собираем пул заново.
    let mut смещения = Vec::with_capacity(число);
    let mut тело = Vec::new();
    for с in &строки {
        смещения.push(тело.len() as u32);
        записать_строку_пула(с, utf8, &mut тело)?;
    }
    while тело.len() % 4 != 0 {
        тело.push(0);
    }
    let новое_начало_строк = 28 + 4 * число;
    let новый_размер = новое_начало_строк + тело.len();
    let mut выход = Vec::with_capacity(данные.len() + тело.len());
    выход.extend_from_slice(&0x0003u16.to_le_bytes());
    выход.extend_from_slice(&8u16.to_le_bytes());
    let хвост = &данные[п + размер_пула..];
    выход.extend_from_slice(&((8 + новый_размер + хвост.len()) as u32).to_le_bytes());
    выход.extend_from_slice(&0x0001u16.to_le_bytes());
    выход.extend_from_slice(&28u16.to_le_bytes());
    выход.extend_from_slice(&(новый_размер as u32).to_le_bytes());
    выход.extend_from_slice(&(число as u32).to_le_bytes());
    выход.extend_from_slice(&0u32.to_le_bytes());
    // Флаг «отсортировано» (0x1) сбрасываем: порядок строк мог измениться.
    выход.extend_from_slice(&(флаги & !0x1).to_le_bytes());
    выход.extend_from_slice(&(новое_начало_строк as u32).to_le_bytes());
    выход.extend_from_slice(&0u32.to_le_bytes());
    for с in &смещения {
        выход.extend_from_slice(&с.to_le_bytes());
    }
    выход.extend_from_slice(&тело);
    выход.extend_from_slice(хвост);
    Ok(выход)
}

// ─────────────────────────── Кодирование ───────────────────────────

fn base64(данные: &[u8]) -> String {
    const А: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut с = String::new();
    for кусок in данные.chunks(3) {
        let б = [кусок[0], *кусок.get(1).unwrap_or(&0), *кусок.get(2).unwrap_or(&0)];
        с.push(А[(б[0] >> 2) as usize] as char);
        с.push(А[(((б[0] & 3) << 4) | (б[1] >> 4)) as usize] as char);
        с.push(if кусок.len() > 1 { А[(((б[1] & 15) << 2) | (б[2] >> 6)) as usize] as char } else { '=' });
        с.push(if кусок.len() > 2 { А[(б[2] & 63) as usize] as char } else { '=' });
    }
    с
}

fn в_hex(б: &[u8]) -> String {
    б.iter().map(|x| format!("{:02x}", x)).collect()
}

fn из_hex(с: &str) -> Result<Vec<u8>, String> {
    let с = с.trim();
    if с.len() % 2 != 0 {
        return Err("повреждён файл ключа".to_string());
    }
    (0..с.len())
        .step_by(2)
        .map(|и| u8::from_str_radix(&с[и..и + 2], 16).map_err(|_| "повреждён файл ключа".to_string()))
        .collect()
}

fn sha256(данные: &[u8]) -> [u8; 32] {
    let mut х = Sha256::new();
    х.update(данные);
    х.finalize().into()
}

// DER

fn der(тег: u8, содержимое: &[u8]) -> Vec<u8> {
    let mut в = vec![тег];
    let д = содержимое.len();
    if д < 0x80 {
        в.push(д as u8);
    } else if д <= 0xff {
        в.extend_from_slice(&[0x81, д as u8]);
    } else if д <= 0xffff {
        в.extend_from_slice(&[0x82, (д >> 8) as u8, (д & 0xff) as u8]);
    } else {
        в.extend_from_slice(&[0x83, (д >> 16) as u8, ((д >> 8) & 0xff) as u8, (д & 0xff) as u8]);
    }
    в.extend_from_slice(содержимое);
    в
}

fn соединить(части: &[&[u8]]) -> Vec<u8> {
    части.iter().flat_map(|ч| ч.iter().copied()).collect()
}

const OID_ECDSA_SHA256: &[u8] = &[0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02];
const OID_EC_PUBLIC_KEY: &[u8] = &[0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01];
const OID_PRIME256V1: &[u8] = &[0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07];
const OID_SHA256: &[u8] = &[0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01];
const OID_DATA: &[u8] = &[0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01];
const OID_SIGNED_DATA: &[u8] = &[0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02];
const OID_COMMON_NAME: &[u8] = &[0x06, 0x03, 0x55, 0x04, 0x03];

fn имя_сертификата() -> Vec<u8> {
    let cn = der(0x30, &соединить(&[OID_COMMON_NAME, &der(0x0C, "Sfera".as_bytes())]));
    der(0x30, &der(0x31, &cn))
}

// ───────────────────────────── Ключ ─────────────────────────────

struct Ключ {
    подпись: SigningKey,
    сертификат: Vec<u8>,
}

fn собрать_сертификат(ключ: &SigningKey, серийный: &[u8; 8]) -> Vec<u8> {
    let точка = ключ.verifying_key().to_encoded_point(false);
    let mut биты = vec![0u8];
    биты.extend_from_slice(точка.as_bytes());
    let алгоритм = der(0x30, OID_ECDSA_SHA256);
    let spki = der(0x30, &соединить(&[&der(0x30, &соединить(&[OID_EC_PUBLIC_KEY, OID_PRIME256V1])), &der(0x03, &биты)]));
    let срок = der(0x30, &соединить(&[&der(0x17, b"200101000000Z"), &der(0x18, b"20700101000000Z")]));
    let mut номер = серийный.to_vec();
    номер[0] &= 0x7f;
    if номер[0] == 0 {
        номер[0] = 1;
    }
    let tbs = der(
        0x30,
        &соединить(&[
            &der(0xA0, &der(0x02, &[2])),
            &der(0x02, &номер),
            &алгоритм,
            &имя_сертификата(),
            &срок,
            &имя_сертификата(),
            &spki,
        ]),
    );
    let подпись: Signature = ключ.sign(&tbs);
    let mut подпись_бит = vec![0u8];
    подпись_бит.extend_from_slice(подпись.to_der().as_bytes());
    der(0x30, &соединить(&[&tbs, &алгоритм, &der(0x03, &подпись_бит)]))
}

fn путь_ключа_по_умолчанию() -> PathBuf {
    let дом = std::env::var("HOME").or_else(|_| std::env::var("USERPROFILE")).unwrap_or_else(|_| ".".to_string());
    Path::new(&дом).join(".sfera").join("apk-ключ.txt")
}

/// Читает ключ из файла; если файла нет — создаёт новый.
fn загрузить_или_создать_ключ(путь: &Path) -> Result<Ключ, String> {
    if let Ok(текст) = std::fs::read_to_string(путь) {
        let mut секрет = None;
        let mut сертификат = None;
        for строка in текст.lines() {
            if let Some(х) = строка.strip_prefix("ключ ") {
                секрет = Some(из_hex(х)?);
            } else if let Some(х) = строка.strip_prefix("сертификат ") {
                сертификат = Some(из_hex(х)?);
            }
        }
        let секрет = секрет.ok_or("в файле ключа нет строки 'ключ'")?;
        let сертификат = сертификат.ok_or("в файле ключа нет строки 'сертификат'")?;
        let подпись = SigningKey::from_slice(&секрет).map_err(|_| "повреждён секретный ключ в файле ключа".to_string())?;
        return Ok(Ключ { подпись, сертификат });
    }
    let подпись = SigningKey::random(&mut rand_core::OsRng);
    let mut серийный = [0u8; 8];
    rand_core::RngCore::fill_bytes(&mut rand_core::OsRng, &mut серийный);
    let сертификат = собрать_сертификат(&подпись, &серийный);
    if let Some(папка) = путь.parent() {
        let _ = std::fs::create_dir_all(папка);
    }
    let текст = format!("ключ {}\nсертификат {}\n", в_hex(&подпись.to_bytes()), в_hex(&сертификат));
    std::fs::write(путь, текст).map_err(|e| format!("не удалось сохранить ключ {}: {}", путь.display(), e))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(путь, std::fs::Permissions::from_mode(0o600));
    }
    Ok(Ключ { подпись, сертификат })
}

// ───────────────────── Подпись APK (схема v1) ─────────────────────

/// Строки манифеста JAR не длиннее 72 байт: продолжение начинается с пробела.
fn строка_манифеста(строка: &str) -> String {
    let байты = строка.as_bytes();
    let mut выход = String::new();
    let mut н = 0;
    let mut первая = true;
    while н < байты.len() {
        let предел = if первая { 72 } else { 71 };
        let к = (н + предел).min(байты.len());
        if !первая {
            выход.push(' ');
        }
        выход.push_str(&строка[н..к]);
        выход.push_str("\r\n");
        н = к;
        первая = false;
    }
    выход
}

fn это_файл_подписи(имя: &str) -> bool {
    let в = имя.to_uppercase();
    в == "META-INF/MANIFEST.MF"
        || (в.starts_with("META-INF/") && (в.ends_with(".SF") || в.ends_with(".RSA") || в.ends_with(".DSA") || в.ends_with(".EC")))
}

fn подписать(записи: &mut Vec<Запись>, ключ: &Ключ) -> Result<(), String> {
    записи.retain(|з| !это_файл_подписи(&з.имя));
    let mut манифест = String::from("Manifest-Version: 1.0\r\nCreated-By: Sfera APK\r\n\r\n");
    let mut разделы: Vec<(String, String)> = Vec::new();
    for з in записи.iter() {
        if з.имя.ends_with('/') {
            continue;
        }
        let данные = содержимое(з)?;
        let раздел = format!(
            "{}{}\r\n",
            строка_манифеста(&format!("Name: {}", з.имя)),
            строка_манифеста(&format!("SHA-256-Digest: {}", base64(&sha256(&данные))))
        );
        манифест.push_str(&раздел);
        разделы.push((з.имя.clone(), раздел));
    }
    let mut sf = format!(
        "Signature-Version: 1.0\r\nCreated-By: Sfera APK\r\nSHA-256-Digest-Manifest: {}\r\n\r\n",
        base64(&sha256(манифест.as_bytes()))
    );
    for (имя, раздел) in &разделы {
        sf.push_str(&строка_манифеста(&format!("Name: {}", имя)));
        sf.push_str(&строка_манифеста(&format!("SHA-256-Digest: {}", base64(&sha256(раздел.as_bytes())))));
        sf.push_str("\r\n");
    }
    // Подпись файла .SF и контейнер PKCS#7.
    let подпись: Signature = ключ.подпись.sign(sf.as_bytes());
    let подпись_der = подпись.to_der();
    let sha_алг = der(0x30, &соединить(&[OID_SHA256, &[0x05, 0x00]]));
    // Серийный номер и издатель берём из самого сертификата: SEQ{ TBS{ [0], serial, ... } }.
    let (издатель_и_номер, ) = {
        let (_, тело_серт) = разобрать_der(&ключ.сертификат)?;
        let (_, tbs) = разобрать_der(тело_серт)?;
        let mut п = tbs;
        let (_, после_версии) = пропустить_элемент(п)?; // [0] версия
        п = после_версии;
        let (длина_номера, _) = длина_элемента(п)?;
        let номер = &п[..длина_номера];
        п = &п[длина_номера..];
        let (д_алг, _) = длина_элемента(п)?;
        п = &п[д_алг..];
        let (д_изд, _) = длина_элемента(п)?;
        let издатель = &п[..д_изд];
        (der(0x30, &соединить(&[издатель, номер])), )
    };
    let signer_info = der(
        0x30,
        &соединить(&[
            &der(0x02, &[1]),
            &издатель_и_номер,
            &sha_алг,
            &der(0x30, OID_ECDSA_SHA256),
            &der(0x04, подпись_der.as_bytes()),
        ]),
    );
    let signed_data = der(
        0x30,
        &соединить(&[
            &der(0x02, &[1]),
            &der(0x31, &sha_алг),
            &der(0x30, OID_DATA),
            &der(0xA0, &ключ.сертификат),
            &der(0x31, &signer_info),
        ]),
    );
    let pkcs7 = der(0x30, &соединить(&[OID_SIGNED_DATA, &der(0xA0, &signed_data)]));
    записи.push(запись_из_данных("META-INF/MANIFEST.MF", манифест.as_bytes(), true));
    записи.push(запись_из_данных("META-INF/CERT.SF", sf.as_bytes(), true));
    записи.push(запись_из_данных("META-INF/CERT.EC", &pkcs7, true));
    Ok(())
}

/// Возвращает (общая длина элемента, его содержимое) для DER-элемента в начале среза.
fn разобрать_der(б: &[u8]) -> Result<(u8, &[u8]), String> {
    let (общая, заголовок) = длина_элемента(б)?;
    Ok((б[0], &б[заголовок..общая]))
}

fn длина_элемента(б: &[u8]) -> Result<(usize, usize), String> {
    let ош = || "повреждён сертификат".to_string();
    let первый = *б.get(1).ok_or_else(ош)? as usize;
    let (длина, заголовок) = if первый < 0x80 {
        (первый, 2)
    } else {
        let н = первый & 0x7f;
        let mut д = 0usize;
        for и in 0..н {
            д = (д << 8) | *б.get(2 + и).ok_or_else(ош)? as usize;
        }
        (д, 2 + н)
    };
    if заголовок + длина > б.len() {
        return Err(ош());
    }
    Ok((заголовок + длина, заголовок))
}

fn пропустить_элемент(б: &[u8]) -> Result<((), &[u8]), String> {
    let (общая, _) = длина_элемента(б)?;
    Ok(((), &б[общая..]))
}

// ─────────────────────────── Упаковка ───────────────────────────

fn латиницей(с: &str) -> String {
    let таблица = [
        ('а', "a"), ('б', "b"), ('в', "v"), ('г', "g"), ('д', "d"), ('е', "e"), ('ё', "e"), ('ж', "zh"),
        ('з', "z"), ('и', "i"), ('й', "y"), ('к', "k"), ('л', "l"), ('м', "m"), ('н', "n"), ('о', "o"),
        ('п', "p"), ('р', "r"), ('с', "s"), ('т', "t"), ('у', "u"), ('ф', "f"), ('х', "h"), ('ц', "c"),
        ('ч', "ch"), ('ш', "sh"), ('щ', "sch"), ('ъ', ""), ('ы', "y"), ('ь', ""), ('э', "e"), ('ю', "yu"),
        ('я', "ya"),
    ];
    let mut в = String::new();
    for с in с.to_lowercase().chars() {
        if с.is_ascii_alphanumeric() {
            в.push(с);
        } else if let Some((_, л)) = таблица.iter().find(|(к, _)| *к == с) {
            в.push_str(л);
        } else {
            в.push('_');
        }
    }
    в
}

/// Идентификатор приложения вида ru.sfera.app.<имя>: латиница, цифры и «_», начинается с буквы.
fn пакет_по_имени(имя: &str) -> String {
    let mut часть = латиницей(имя).trim_matches('_').to_string();
    if часть.is_empty() {
        часть = "app".to_string();
    }
    if !часть.chars().next().unwrap().is_ascii_alphabetic() {
        часть = format!("app{}", часть);
    }
    format!("ru.sfera.app.{}", часть)
}

fn пакет_допустим(п: &str) -> bool {
    let части: Vec<&str> = п.split('.').collect();
    части.len() >= 2
        && части.iter().all(|ч| {
            !ч.is_empty()
                && ч.chars().next().unwrap().is_ascii_alphabetic()
                && ч.chars().all(|с| с.is_ascii_alphanumeric() || с == '_')
        })
}

struct Параметры {
    шаблон: PathBuf,
    библиотека: PathBuf,
    имя: String,
    пакет: Option<String>,
    ключ: PathBuf,
    выход: PathBuf,
    шаблонный_пакет: String,
    шаблонное_имя: String,
}

fn упаковать(п: &Параметры) -> Result<(), String> {
    let пакет = п.пакет.clone().unwrap_or_else(|| пакет_по_имени(&п.имя));
    if !пакет_допустим(&пакет) {
        return Err(format!("недопустимый идентификатор '{}': нужны латиница, цифры и «_», части через точку (ru.sfera.moя_игра — нельзя, ru.sfera.moya_igra — можно)", пакет));
    }
    if п.имя.trim().is_empty() {
        return Err("пустое имя приложения".to_string());
    }
    let шаблон = std::fs::read(&п.шаблон).map_err(|e| format!("не удалось прочитать шаблон {}: {}", п.шаблон.display(), e))?;
    let so = std::fs::read(&п.библиотека).map_err(|e| format!("не удалось прочитать {}: {}", п.библиотека.display(), e))?;
    if so.len() < 4 || &so[..4] != b"\x7fELF" {
        return Err(format!("{} — не библиотека (нет заголовка ELF)", п.библиотека.display()));
    }
    let mut записи = прочитать_zip(&шаблон)?;
    let мест = записи.iter().position(|з| з.имя == "lib/arm64-v8a/libmain.so").ok_or("в шаблоне нет lib/arm64-v8a/libmain.so")?;
    записи[мест] = запись_из_данных("lib/arm64-v8a/libmain.so", &so, false);
    let мест = записи.iter().position(|з| з.имя == "AndroidManifest.xml").ok_or("в шаблоне нет AndroidManifest.xml")?;
    let манифест = заменить_строки_манифеста(
        &содержимое(&записи[мест])?,
        &[(п.шаблонный_пакет.clone(), пакет.clone()), (п.шаблонное_имя.clone(), п.имя.clone())],
    )?;
    записи[мест] = запись_из_данных("AndroidManifest.xml", &манифест, true);
    let ключ = загрузить_или_создать_ключ(&п.ключ)?;
    подписать(&mut записи, &ключ)?;
    let байты = записать_zip(&записи);
    if let Some(папка) = п.выход.parent() {
        if !папка.as_os_str().is_empty() {
            let _ = std::fs::create_dir_all(папка);
        }
    }
    std::fs::write(&п.выход, &байты).map_err(|e| format!("не удалось записать {}: {}", п.выход.display(), e))?;
    println!("Готово: {} ({:.1} МБ)", п.выход.display(), байты.len() as f64 / 1048576.0);
    println!("Приложение: «{}», идентификатор {}", п.имя, пакет);
    Ok(())
}

fn подсказка() {
    println!("сфера_apk — упаковка программы Сферы в Android-приложение (.apk)");
    println!();
    println!("  сфера_apk упаковать --шаблон ШАБЛОН.apk --библиотека libmain.so --имя \"Название\" --выход ПРИЛОЖЕНИЕ.apk");
    println!("                      [--пакет ru.sfera.app.моё] [--ключ ФАЙЛ]");
    println!("  сфера_apk ключ [ФАЙЛ]   создать ключ подписи (если его нет)");
    println!("  сфера_apk извлечь-библиотеки ШАБЛОН.apk ПАПКА");
    println!();
    println!("Шаблон собирает собрать-apk.sh (Sfera-App-Template.apk), он же лежит внутри панели Android.");
    println!("Ключ по умолчанию: ~/.sfera/apk-ключ.txt. Приложения, подписанные одним ключом, обновляются поверх друг друга.");
}

fn главная() -> Result<(), String> {
    let аргументы: Vec<String> = std::env::args().collect();
    match аргументы.get(1).map(String::as_str) {
        Some("упаковать") => {
            let mut п = Параметры {
                шаблон: PathBuf::new(),
                библиотека: PathBuf::new(),
                имя: String::new(),
                пакет: None,
                ключ: путь_ключа_по_умолчанию(),
                выход: PathBuf::new(),
                шаблонный_пакет: "ru.sfera.app".to_string(),
                шаблонное_имя: "Приложение Сферы".to_string(),
            };
            let mut и = 2;
            while и < аргументы.len() {
                let значение = |и: usize| аргументы.get(и + 1).cloned().ok_or_else(|| format!("после {} нужно значение", аргументы[и]));
                match аргументы[и].as_str() {
                    "--шаблон" => п.шаблон = PathBuf::from(значение(и)?),
                    "--библиотека" => п.библиотека = PathBuf::from(значение(и)?),
                    "--имя" => п.имя = значение(и)?,
                    "--пакет" => п.пакет = Some(значение(и)?),
                    "--ключ" => п.ключ = PathBuf::from(значение(и)?),
                    "--выход" => п.выход = PathBuf::from(значение(и)?),
                    "--шаблонный-пакет" => п.шаблонный_пакет = значение(и)?,
                    "--шаблонное-имя" => п.шаблонное_имя = значение(и)?,
                    другое => return Err(format!("неизвестный параметр '{}'", другое)),
                }
                и += 2;
            }
            if п.шаблон.as_os_str().is_empty() || п.библиотека.as_os_str().is_empty() || п.выход.as_os_str().is_empty() || п.имя.is_empty() {
                return Err("нужны параметры --шаблон, --библиотека, --имя и --выход (см. 'сфера_apk' без аргументов)".to_string());
            }
            упаковать(&п)
        }
        Some("извлечь-библиотеки") => {
            // Достаёт из шаблона libSDL2.so и др. — они нужны компилятору при сборке под Android.
            let (шаблон, папка) = match (аргументы.get(2), аргументы.get(3)) {
                (Some(а), Some(б)) => (а, б),
                _ => return Err("использование: сфера_apk извлечь-библиотеки ШАБЛОН.apk ПАПКА".to_string()),
            };
            let байты = std::fs::read(шаблон).map_err(|e| format!("не удалось прочитать {}: {}", шаблон, e))?;
            std::fs::create_dir_all(папка).map_err(|e| format!("не удалось создать {}: {}", папка, e))?;
            let mut число = 0;
            for з in прочитать_zip(&байты)? {
                if let Some(имя) = з.имя.strip_prefix("lib/arm64-v8a/") {
                    if имя.ends_with(".so") && имя != "libmain.so" && !имя.contains('/') {
                        std::fs::write(Path::new(папка).join(имя), содержимое(&з)?)
                            .map_err(|e| format!("не удалось записать {}: {}", имя, e))?;
                        число += 1;
                    }
                }
            }
            println!("Извлечено библиотек: {}", число);
            Ok(())
        }
        Some("ключ") => {
            let путь = аргументы.get(2).map(PathBuf::from).unwrap_or_else(путь_ключа_по_умолчанию);
            let ключ = загрузить_или_создать_ключ(&путь)?;
            println!("Ключ: {}", путь.display());
            println!("Отпечаток сертификата (SHA-256): {}", в_hex(&sha256(&ключ.сертификат)));
            Ok(())
        }
        _ => {
            подсказка();
            Ok(())
        }
    }
}

fn main() {
    if let Err(е) = главная() {
        eprintln!("Ошибка: {}", е);
        std::process::exit(1);
    }
}

#[cfg(test)]
mod тесты {
    use super::*;

    fn строка_утф8(с: &str) -> Vec<u8> {
        let mut в = Vec::new();
        записать_строку_пула(с, true, &mut в).unwrap();
        в
    }

    /// Минимальный манифест: файловый заголовок + пул строк (+ «хвост» из произвольных байт).
    fn пробный_манифест(строки: &[&str], utf8: bool) -> Vec<u8> {
        let mut смещения = Vec::new();
        let mut тело = Vec::new();
        for с in строки {
            смещения.push(тело.len() as u32);
            if utf8 {
                тело.extend(строка_утф8(с));
            } else {
                записать_строку_пула(с, false, &mut тело).unwrap();
            }
        }
        while тело.len() % 4 != 0 {
            тело.push(0);
        }
        let начало = 28 + 4 * строки.len();
        let размер_пула = начало + тело.len();
        let хвост = [0x80u8, 0x01, 0x08, 0x00, 8, 0, 0, 0];
        let mut в = Vec::new();
        в.extend_from_slice(&3u16.to_le_bytes());
        в.extend_from_slice(&8u16.to_le_bytes());
        в.extend_from_slice(&((8 + размер_пула + хвост.len()) as u32).to_le_bytes());
        в.extend_from_slice(&1u16.to_le_bytes());
        в.extend_from_slice(&28u16.to_le_bytes());
        в.extend_from_slice(&(размер_пула as u32).to_le_bytes());
        в.extend_from_slice(&(строки.len() as u32).to_le_bytes());
        в.extend_from_slice(&0u32.to_le_bytes());
        в.extend_from_slice(&(if utf8 { 0x100u32 } else { 0 } | 1).to_le_bytes());
        в.extend_from_slice(&(начало as u32).to_le_bytes());
        в.extend_from_slice(&0u32.to_le_bytes());
        for с in &смещения {
            в.extend_from_slice(&с.to_le_bytes());
        }
        в.extend_from_slice(&тело);
        в.extend_from_slice(&хвост);
        в
    }

    fn строки_пула(м: &[u8]) -> Vec<String> {
        let п = 8;
        let заг = u16_из(м, п + 2).unwrap() as usize;
        let число = u32_из(м, п + 8).unwrap() as usize;
        let флаги = u32_из(м, п + 16).unwrap();
        let нач = u32_из(м, п + 20).unwrap() as usize;
        let размер = u32_из(м, п + 4).unwrap() as usize;
        let пул = &м[п..п + размер];
        (0..число)
            .map(|и| {
                let см = u32_из(пул, заг + 4 * и).unwrap() as usize;
                прочитать_строку_пула(пул, нач + см, флаги & 0x100 != 0).unwrap()
            })
            .collect()
    }

    #[test]
    fn манифест_замена_в_обоих_форматах_строк() {
        for utf8 in [true, false] {
            let м = пробный_манифест(&["manifest", "ru.sfera.app", "Приложение Сферы", "package", "android.intent.action.MAIN"], utf8);
            let н = заменить_строки_манифеста(
                &м,
                &[("ru.sfera.app".to_string(), "ru.sfera.app.moya_igra_с_очень_длинным_названием".to_string()), ("Приложение Сферы".to_string(), "Игра".to_string())],
            )
            .unwrap();
            let с = строки_пула(&н);
            assert_eq!(с[1], "ru.sfera.app.moya_igra_с_очень_длинным_названием", "utf8={}", utf8);
            assert_eq!(с[2], "Игра");
            assert_eq!(с[0], "manifest");
            assert_eq!(с[4], "android.intent.action.MAIN");
            // общая длина в заголовке совпадает с реальной, хвост на месте
            assert_eq!(u32_из(&н, 4).unwrap() as usize, н.len());
            assert_eq!(&н[н.len() - 8..], &[0x80, 0x01, 0x08, 0x00, 8, 0, 0, 0]);
        }
    }

    #[test]
    fn манифест_без_нужных_строк_отвергается() {
        let м = пробный_манифест(&["manifest", "другое"], true);
        assert!(заменить_строки_манифеста(&м, &[("ru.sfera.app".to_string(), "x.y".to_string())]).is_err());
    }

    #[test]
    fn zip_туда_и_обратно() {
        let а = запись_из_данных("a.txt", &vec![b'x'; 1000], true);
        let б = запись_из_данных("папка/б.bin", &[1, 2, 3], false);
        assert_eq!(а.метод, 8);
        assert_eq!(б.метод, 0);
        let архив = записать_zip(&[а.clone(), б.clone()]);
        let назад = прочитать_zip(&архив).unwrap();
        assert_eq!(назад.len(), 2);
        assert_eq!(содержимое(&назад[0]).unwrap(), vec![b'x'; 1000]);
        assert_eq!(назад[1].имя, "папка/б.bin");
        assert_eq!(содержимое(&назад[1]).unwrap(), vec![1, 2, 3]);
        assert_eq!(назад[0].crc, crc32(&vec![b'x'; 1000]));
    }

    #[test]
    fn имя_пакета_из_русского_названия() {
        assert_eq!(пакет_по_имени("Моя игра"), "ru.sfera.app.moya_igra");
        assert_eq!(пакет_по_имени("2048"), "ru.sfera.app.app2048");
        assert_eq!(пакет_по_имени("!!!"), "ru.sfera.app.app");
        assert!(пакет_допустим("ru.sfera.app.moya_igra"));
        assert!(!пакет_допустим("ru.sfera.игра"));
        assert!(!пакет_допустим("single"));
    }

    #[test]
    fn строки_манифеста_jar_делятся_на_72_байта() {
        let длинная = format!("Name: {}", "a".repeat(100));
        let с = строка_манифеста(&длинная);
        for л in с.split("\r\n").filter(|л| !л.is_empty()) {
            assert!(л.len() <= 72);
        }
        assert!(с.contains("\r\n "));
        assert_eq!(с.replace("\r\n ", "").trim_end(), длинная);
    }

    #[test]
    fn base64_как_у_стандарта() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
    }
}
