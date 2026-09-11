//! Языковой сервер (Language Server Protocol) для языка "Сфера" — v2.
//!
//! РЕАЛИЗОВАНО:
//! - Диагностика ошибок в реальном времени (см. v1) — прогоняет лексер +
//!   парсер + семантику из библиотечной цели (src/lib.rs), без кодогенерации.
//! - НОВОЕ: автодополнение (textDocument/completion) — ключевые слова,
//!   встроенные типы, функции стандартной библиотеки (статический список,
//!   src/подсказки.rs), плюс функции и структуры, объявленные В ТЕКУЩЕМ
//!   ОТКРЫТОМ ФАЙЛЕ (собираются заново при каждом изменении, вместе с
//!   диагностикой).
//! - НОВОЕ: подсказки при наведении (textDocument/hover) — показывает
//!   сигнатуру функции/метода или поля структуры под курсором.
//!
//! НЕ РЕАЛИЗОВАНО (следующий, отдельный шаг): "перейти к определению",
//! подсказки параметров при вызове (signature help). Оба требуют, чтобы
//! AST хранил позиции объявлений в исходном тексте — этого сейчас нет
//! вообще (ни в одном узле AST), добавление такой инфраструктуры — заметно
//! более крупная, самостоятельная задача, не расширение уже готового кода.
//!
//! ⚠️ ИЗВЕСТНЫЕ ОГРАНИЧЕНИЯ:
//!
//! 1. Многофайловые проекты (с "подключить") — диагностика и автодополнение
//!    видят ТОЛЬКО открытый файл изолированно (та же граница, что и в v1).
//!
//! 2. Автодополнение переменных ИЗ ТЕКУЩЕЙ ФУНКЦИИ не реализовано вообще —
//!    только функции/структуры верхнего уровня. Переменные требуют
//!    отслеживания области видимости "что видно в этой конкретной точке
//!    курсора", что понадобилось бы делать отдельно, тщательно, а не
//!    "заодно" — сознательно отложено, не забыто.
//!
//! 3. Hover находит слово под курсором ТЕКСТОВЫМ способом (простой поиск
//!    границ идентификатора в сыром тексте документа), а не через AST —
//!    так же, как в п.2, потому что AST не хранит позиции. Это устойчивый,
//!    распространённый приём для базового hover без полной инфраструктуры
//!    позиций, но менее точный: например, не отличит "юзер" в "юзер.имя"
//!    от "юзер" где-то в комментарии, если бы курсор туда попал (хотя
//!    попадание курсора В комментарий и не должно давать полезный hover
//!    в любом случае).
//!
//! ⚠️ Эта версия ПРОВЕРЕНА мной локально (компиляция + реальные
//! JSON-RPC запросы через stdin/stdout) перед отправкой — включая
//! completion и hover, не только изначальную диагностику.

use std::collections::HashMap;

use lsp_server::{Connection, Message, Notification as ЛспУведомление, Request as ЛспЗапрос, RequestId, Response as ЛспОтвет};
use lsp_types::{
    notification::{
        DidChangeTextDocument, DidCloseTextDocument, DidOpenTextDocument, Notification,
        PublishDiagnostics,
    },
    request::{Completion, GotoDefinition, HoverRequest, Request as ЗапросТрейт},
    CompletionItem, CompletionItemKind, CompletionParams, CompletionResponse,
    Diagnostic, DiagnosticSeverity, DidChangeTextDocumentParams, DidCloseTextDocumentParams,
    DidOpenTextDocumentParams, GotoDefinitionParams, GotoDefinitionResponse, Hover, HoverContents,
    HoverParams, HoverProviderCapability, InitializeParams, Location, MarkupContent, MarkupKind,
    OneOf, Position, PublishDiagnosticsParams, Range,
    ServerCapabilities, TextDocumentSyncCapability, TextDocumentSyncKind, Url,
};

use sfera::ast::{ВерхнийУзел, Программа};
use sfera::lexer::Лексер;
use sfera::parser::Парсер;
use sfera::semantic::СемантическийАнализатор;
use sfera::подсказки::{тип_в_текст, статические_подсказки, ВидПодсказки};

/// Состояние сервера между запросами — единственное, что нужно хранить:
/// последний известный текст каждого ОТКРЫТОГО документа (по его URI).
/// Нужно для hover и completion — оба запроса приходят БЕЗ текста документа
/// (в отличие от didOpen/didChange), редактор ожидает, что сервер сам
/// помнит содержимое уже открытых файлов.
struct СостояниеСервера {
    документы: HashMap<Url, String>,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let (соединение, потоки_ввода_вывода) = Connection::stdio();

    let возможности_сервера = serde_json::to_value(ServerCapabilities {
        text_document_sync: Some(TextDocumentSyncCapability::Kind(TextDocumentSyncKind::FULL)),
        // НОВОЕ: заявляем поддержку автодополнения и hover — без этого
        // редактор даже не станет ПОСЫЛАТЬ нам соответствующие запросы.
        completion_provider: Some(Default::default()),
        hover_provider: Some(HoverProviderCapability::Simple(true)),
        // НОВОЕ: заявляем поддержку "перейти к определению".
        definition_provider: Some(OneOf::Left(true)),
        ..Default::default()
    })?;

    let параметры_инициализации = соединение.initialize(возможности_сервера)?;
    let _параметры: InitializeParams = serde_json::from_value(параметры_инициализации)?;

    let mut состояние = СостояниеСервера { документы: HashMap::new() };
    основной_цикл(&соединение, &mut состояние)?;
    потоки_ввода_вывода.join()?;
    Ok(())
}

fn основной_цикл(соединение: &Connection, состояние: &mut СостояниеСервера) -> Result<(), Box<dyn std::error::Error>> {
    for сообщение in &соединение.receiver {
        match сообщение {
            Message::Request(запрос) => {
                if соединение.handle_shutdown(&запрос)? {
                    return Ok(());
                }
                обработать_запрос(соединение, состояние, запрос)?;
            }
            Message::Response(_) => {}
            Message::Notification(уведомление) => {
                обработать_уведомление(соединение, состояние, уведомление)?;
            }
        }
    }
    Ok(())
}

fn обработать_запрос(соединение: &Connection, состояние: &СостояниеСервера, запрос: ЛспЗапрос) -> Result<(), Box<dyn std::error::Error>> {
    match запрос.method.as_str() {
        Completion::METHOD => {
            let параметры: CompletionParams = serde_json::from_value(запрос.params)?;
            let uri = &параметры.text_document_position.text_document.uri;
            let элементы = собрать_автодополнение(состояние.документы.get(uri).map(String::as_str).unwrap_or(""));
            ответить(соединение, запрос.id, CompletionResponse::Array(элементы))?;
        }
        HoverRequest::METHOD => {
            let параметры: HoverParams = serde_json::from_value(запрос.params)?;
            let uri = &параметры.text_document_position_params.text_document.uri;
            let позиция = параметры.text_document_position_params.position;
            let текст = состояние.документы.get(uri).map(String::as_str).unwrap_or("");
            match собрать_hover(текст, позиция) {
                Some(hover) => ответить(соединение, запрос.id, hover)?,
                None => ответить_пусто(соединение, запрос.id)?,
            }
        }
        GotoDefinition::METHOD => {
            let параметры: GotoDefinitionParams = serde_json::from_value(запрос.params)?;
            let uri = &параметры.text_document_position_params.text_document.uri;
            let позиция = параметры.text_document_position_params.position;
            let текст = состояние.документы.get(uri).map(String::as_str).unwrap_or("");
            match собрать_переход_к_определению(текст, позиция, uri) {
                Some(ответ) => ответить(соединение, запрос.id, ответ)?,
                None => ответить_пусто(соединение, запрос.id)?,
            }
        }
        _ => {
            // Остальные запросы (переход к определению, signature help и
            // т.д.) пока не реализованы — см. предупреждение в начале файла.
            ответить_пусто(соединение, запрос.id)?;
        }
    }
    Ok(())
}

fn ответить<T: serde::Serialize>(соединение: &Connection, id: RequestId, значение: T) -> Result<(), Box<dyn std::error::Error>> {
    let ответ = ЛспОтвет { id, result: Some(serde_json::to_value(значение)?), error: None };
    соединение.sender.send(Message::Response(ответ))?;
    Ok(())
}

fn ответить_пусто(соединение: &Connection, id: RequestId) -> Result<(), Box<dyn std::error::Error>> {
    let ответ = ЛспОтвет { id, result: Some(serde_json::Value::Null), error: None };
    соединение.sender.send(Message::Response(ответ))?;
    Ok(())
}

fn обработать_уведомление(соединение: &Connection, состояние: &mut СостояниеСервера, уведомление: ЛспУведомление) -> Result<(), Box<dyn std::error::Error>> {
    match уведомление.method.as_str() {
        DidOpenTextDocument::METHOD => {
            let параметры: DidOpenTextDocumentParams = serde_json::from_value(уведомление.params)?;
            состояние.документы.insert(параметры.text_document.uri.clone(), параметры.text_document.text.clone());
            проверить_и_отправить_диагностики(соединение, &параметры.text_document.uri, &параметры.text_document.text)?;
        }
        DidChangeTextDocument::METHOD => {
            let параметры: DidChangeTextDocumentParams = serde_json::from_value(уведомление.params)?;
            if let Some(изменение) = параметры.content_changes.into_iter().last() {
                состояние.документы.insert(параметры.text_document.uri.clone(), изменение.text.clone());
                проверить_и_отправить_диагностики(соединение, &параметры.text_document.uri, &изменение.text)?;
            }
        }
        DidCloseTextDocument::METHOD => {
            let параметры: DidCloseTextDocumentParams = serde_json::from_value(уведомление.params)?;
            состояние.документы.remove(&параметры.text_document.uri);
            отправить_диагностики(соединение, &параметры.text_document.uri, vec![])?;
        }
        _ => {}
    }
    Ok(())
}

fn проверить_и_отправить_диагностики(соединение: &Connection, uri: &Url, текст: &str) -> Result<(), Box<dyn std::error::Error>> {
    отправить_диагностики(соединение, uri, получить_диагностики(текст))
}

fn отправить_диагностики(соединение: &Connection, uri: &Url, диагностики: Vec<Diagnostic>) -> Result<(), Box<dyn std::error::Error>> {
    let параметры = PublishDiagnosticsParams { uri: uri.clone(), diagnostics: диагностики, version: None };
    let уведомление = ЛспУведомление::new(PublishDiagnostics::METHOD.to_string(), параметры);
    соединение.sender.send(Message::Notification(уведомление))?;
    Ok(())
}

fn получить_диагностики(текст: &str) -> Vec<Diagnostic> {
    let токены = match Лексер::новый(текст).токенизировать() {
        Ok(токены) => токены,
        Err(e) => return vec![диагностика_с_позицией(e.строка, e.столбец, &e.сообщение)],
    };
    let программа = match Парсер::новый(токены).разобрать_программу() {
        Ok(программа) => программа,
        Err(e) => return vec![диагностика_с_позицией(e.строка, e.столбец, &e.сообщение)],
    };
    let mut анализатор = СемантическийАнализатор::новый();
    // Языковой сервер проверяет ТОЛЬКО открытый файл, изолированно (без
    // разрешения "подключить" — известное ограничение, см. предупреждение
    // в начале файла) — значит модулей нет вообще, весь файл считается
    // "главным": пустая карта модулей, и Vec<None> той же длины, что и
    // программа (не короче — иначе .zip() внутри проверить_программу
    // "обрежет" и пропустит проверку части узлов, тихий баг).
    let модули_программы: HashMap<String, std::collections::HashSet<String>> = HashMap::new();
    let модуль_каждого_узла: Vec<Option<String>> = vec![None; программа.len()];
    match анализатор.проверить_программу(&программа, &модули_программы, &модуль_каждого_узла) {
        Ok(()) => vec![],
        Err(e) => vec![диагностика_с_позицией(1, 1, &format!("[без точной позиции] {}", e.сообщение))],
    }
}

fn диагностика_с_позицией(строка: usize, столбец: usize, сообщение: &str) -> Diagnostic {
    let позиция = Position { line: строка.saturating_sub(1) as u32, character: столбец.saturating_sub(1) as u32 };
    Diagnostic {
        range: Range { start: позиция, end: Position { line: позиция.line, character: позиция.character + 1 } },
        severity: Some(DiagnosticSeverity::ERROR),
        source: Some("Сфера".to_string()),
        message: сообщение.to_string(),
        ..Default::default()
    }
}

/// Пытается разобрать текущий текст документа в Программа — используется
/// И автодополнением, И hover, чтобы найти пользовательские функции/
/// структуры. Если текст сейчас невалиден (пользователь ещё не дописал
/// код) — возвращает None, а не падает: автодополнение в этом случае
/// просто покажет только статические подсказки (ключевые слова/типы/
/// stdlib), без пользовательских функций — разумный, а не аварийный отказ.
fn попытаться_разобрать(текст: &str) -> Option<Программа> {
    let токены = Лексер::новый(текст).токенизировать().ok()?;
    Парсер::новый(токены).разобрать_программу().ok()
}

/// Строит список автодополнения: статические подсказки (см. подсказки.rs)
/// + функции и структуры, объявленные в ТЕКУЩЕМ файле (собираются заново
/// при каждом вызове — простой, безопасный подход, не кэширует состояние
/// между запросами, цена пересборки для файла разумного размера мала).
fn собрать_автодополнение(текст: &str) -> Vec<CompletionItem> {
    let mut элементы: Vec<CompletionItem> = статические_подсказки()
        .into_iter()
        .map(|подсказка| CompletionItem {
            label: подсказка.имя.to_string(),
            kind: Some(match подсказка.вид {
                ВидПодсказки::КлючевоеСлово => CompletionItemKind::KEYWORD,
                ВидПодсказки::Тип => CompletionItemKind::CLASS,
                ВидПодсказки::Функция => CompletionItemKind::FUNCTION,
            }),
            detail: Some(подсказка.деталь.to_string()),
            documentation: если_не_пусто(подсказка.документация),
            ..Default::default()
        })
        .collect();

    if let Some(программа) = попытаться_разобрать(текст) {
        for узел in &программа {
            match узел {
                ВерхнийУзел::Функция(ф) => {
                    let параметры_текст: Vec<String> = ф.параметры.iter().map(|п| format!("{} {}", тип_в_текст(&п.тип), п.имя)).collect();
                    let тип_возврата_текст = ф.тип_возврата.as_ref().map(тип_в_текст).unwrap_or_default();
                    let деталь = if тип_возврата_текст.is_empty() {
                        format!("функция({})", параметры_текст.join(", "))
                    } else {
                        format!("функция({}) -> {}", параметры_текст.join(", "), тип_возврата_текст)
                    };
                    элементы.push(CompletionItem {
                        label: ф.имя.clone(),
                        kind: Some(CompletionItemKind::FUNCTION),
                        detail: Some(деталь),
                        ..Default::default()
                    });
                }
                ВерхнийУзел::Структура(с) => {
                    элементы.push(CompletionItem {
                        label: с.имя.clone(),
                        kind: Some(CompletionItemKind::STRUCT),
                        detail: Some(format!("структура ({} полей)", с.поля.len())),
                        ..Default::default()
                    });
                }
                ВерхнийУзел::Подключение(_) => {}
                // НОВОЕ: имя контракта тоже полезно в автодополнении —
                // пригодится при вводе "структура X : ...".
                ВерхнийУзел::Контракт(к) => {
                    элементы.push(CompletionItem {
                        label: к.имя.clone(),
                        kind: Some(CompletionItemKind::INTERFACE),
                        detail: Some(format!("контракт ({} метод(ов))", к.методы.len())),
                        ..Default::default()
                    });
                }
                // НОВОЕ: внешние функции (FFI) тоже полезны в автодополнении.
                ВерхнийУзел::ВнешняяФункция(вф) => {
                    let параметры_текст: Vec<String> = вф.параметры.iter().map(|п| format!("{} {}", тип_в_текст(&п.тип), п.имя)).collect();
                    let тип_возврата_текст = вф.тип_возврата.as_ref().map(тип_в_текст).unwrap_or_default();
                    let деталь = if тип_возврата_текст.is_empty() {
                        format!("внешняя функция({})", параметры_текст.join(", "))
                    } else {
                        format!("внешняя функция({}) -> {}", параметры_текст.join(", "), тип_возврата_текст)
                    };
                    элементы.push(CompletionItem {
                        label: вф.имя.clone(),
                        kind: Some(CompletionItemKind::FUNCTION),
                        detail: Some(деталь),
                        ..Default::default()
                    });
                }
            }
        }
    }

    элементы
}

fn если_не_пусто(текст: &str) -> Option<lsp_types::Documentation> {
    if текст.is_empty() {
        None
    } else {
        Some(lsp_types::Documentation::String(текст.to_string()))
    }
}

/// Находит подсказку при наведении — сначала извлекает слово под курсором
/// ТЕКСТОВЫМ способом (см. предупреждение в начале файла про то, почему не
/// через AST), затем ищет это слово среди статических подсказок и среди
/// функций/структур текущего файла.
fn собрать_hover(текст: &str, позиция: Position) -> Option<Hover> {
    let слово = слово_под_курсором(текст, позиция)?;

    // Сначала — статические подсказки (ключевые слова/типы/stdlib).
    for подсказка in статические_подсказки() {
        if подсказка.имя == слово {
            let содержимое = if подсказка.документация.is_empty() {
                format!("**{}**\n\n{}", подсказка.имя, подсказка.деталь)
            } else {
                format!("**{}**\n\n{}\n\n{}", подсказка.имя, подсказка.деталь, подсказка.документация)
            };
            return Some(построить_hover(содержимое));
        }
    }

    // Затем — функции/структуры текущего файла.
    let программа = попытаться_разобрать(текст)?;
    for узел in &программа {
        match узел {
            ВерхнийУзел::Функция(ф) if ф.имя == слово => {
                let параметры_текст: Vec<String> = ф.параметры.iter().map(|п| format!("{} {}", тип_в_текст(&п.тип), п.имя)).collect();
                let тип_возврата_текст = ф.тип_возврата.as_ref().map(|т| format!(" -> {}", тип_в_текст(т))).unwrap_or_default();
                let содержимое = format!("```\nфункция {}({}){}\n```", ф.имя, параметры_текст.join(", "), тип_возврата_текст);
                return Some(построить_hover(содержимое));
            }
            ВерхнийУзел::Структура(с) if с.имя == слово => {
                let поля_текст: Vec<String> = с.поля.iter().map(|поле| format!("    {} {};", тип_в_текст(&поле.тип), поле.имя)).collect();
                let содержимое = format!("```\nструктура {} {{\n{}\n}}\n```", с.имя, поля_текст.join("\n"));
                return Some(построить_hover(содержимое));
            }
            ВерхнийУзел::Структура(с) => {
                // Заодно проверяем МЕТОДЫ этой структуры — курсор может
                // стоять на имени метода, не только на имени самой структуры.
                for метод in &с.методы {
                    if метод.имя == слово {
                        let параметры_текст: Vec<String> = метод.параметры.iter().map(|п| format!("{} {}", тип_в_текст(&п.тип), п.имя)).collect();
                        let тип_возврата_текст = метод.тип_возврата.as_ref().map(|т| format!(" -> {}", тип_в_текст(т))).unwrap_or_default();
                        let содержимое = format!("```\n{}.{}({}){}\n```", с.имя, метод.имя, параметры_текст.join(", "), тип_возврата_текст);
                        return Some(построить_hover(содержимое));
                    }
                }
            }
            _ => {}
        }
    }

    None
}

fn построить_hover(содержимое: String) -> Hover {
    Hover {
        contents: HoverContents::Markup(MarkupContent { kind: MarkupKind::Markdown, value: содержимое }),
        range: None,
    }
}

/// НОВОЕ: "перейти к определению" — та же логика поиска слова под курсором,
/// что и у hover (см. предупреждение в начале файла про текстовый способ),
/// но вместо описания возвращает МЕСТОПОЛОЖЕНИЕ объявления в файле —
/// возможно благодаря новому полю "позиция" в AST (ОбъявлениеФункции/
/// ОбъявлениеСтруктуры), которое раньше не отслеживалось вообще (компилятору
/// оно не нужно для генерации кода, только языковому серверу).
///
/// ⚠️ v1 — только функции, структуры и методы. Контракты и переменные —
/// не поддержаны (контракты пока не несут позицию в AST; переменные не
/// имеют одного "места объявления", удобного для перехода — они могут
/// быть переприсвоены много раз, семантика для этого случая сложнее).
fn собрать_переход_к_определению(текст: &str, позиция: Position, uri: &Url) -> Option<GotoDefinitionResponse> {
    let слово = слово_под_курсором(текст, позиция)?;
    let программа = попытаться_разобрать(текст)?;

    for узел in &программа {
        match узел {
            ВерхнийУзел::Функция(ф) if ф.имя == слово => {
                return построить_location_ответ(uri, ф.позиция);
            }
            ВерхнийУзел::Структура(с) if с.имя == слово => {
                return построить_location_ответ(uri, с.позиция);
            }
            ВерхнийУзел::Структура(с) => {
                for метод in &с.методы {
                    if метод.имя == слово {
                        return построить_location_ответ(uri, метод.позиция);
                    }
                }
            }
            _ => {}
        }
    }

    None
}

fn построить_location_ответ(uri: &Url, позиция: Option<(usize, usize)>) -> Option<GotoDefinitionResponse> {
    // Позиция в AST — 1-индексированная (строка 1, столбец 1 — как в
    // обычных человекочитаемых сообщениях компилятора), а LSP использует
    // 0-индексированные позиции — та же вычитка через saturating_sub, что
    // уже применена в диагностике (диагностика_с_позицией).
    let (строка, столбец) = позиция?;
    let lsp_позиция = Position {
        line: строка.saturating_sub(1) as u32,
        character: столбец.saturating_sub(1) as u32,
    };
    let диапазон = Range { start: lsp_позиция, end: lsp_позиция };
    Some(GotoDefinitionResponse::Scalar(Location { uri: uri.clone(), range: диапазон }))
}

/// Извлекает слово (идентификатор) под курсором — ЧИСТО ТЕКСТОВЫЙ способ,
/// без обращения к AST (см. подробное объяснение в начале файла). Работает
/// построчно, посимвольно — ищет границы идентификатора (буквы, цифры,
/// подчёркивание — всё остальное считается границей) вокруг указанного
/// столбца.
///
/// ⚠️ LSP использует UTF-16 code unit смещения для character в Position
/// (особенность самого протокола) — а кириллица в UTF-16 кодируется 1
/// code unit'ом на символ (в отличие от UTF-8, где 2 БАЙТА на символ) —
/// значит нужно считать по СИМВОЛАМ (chars), не по байтам, чтобы позиция
/// совпадала с тем, что редактор реально имел в виду.
fn слово_под_курсором(текст: &str, позиция: Position) -> Option<String> {
    let строка = текст.lines().nth(позиция.line as usize)?;
    let символы: Vec<char> = строка.chars().collect();
    let индекс = (позиция.character as usize).min(символы.len());

    let является_частью_слова = |c: char| c.is_alphanumeric() || c == '_';

    if символы.is_empty() {
        return None;
    }

    // Ищем влево и вправо от курсора границы идентификатора. Если курсор
    // стоит ровно на границе (между словом и не-словом), пробуем сначала
    // символ СЛЕВА от курсора (типичное поведение большинства LSP при
    // наведении ровно на конец слова).
    let точка_проверки = if индекс > 0 && (индекс == символы.len() || !является_частью_слова(символы[индекс])) {
        индекс - 1
    } else {
        индекс
    };

    if точка_проверки >= символы.len() || !является_частью_слова(символы[точка_проверки]) {
        return None;
    }

    let mut начало = точка_проверки;
    while начало > 0 && является_частью_слова(символы[начало - 1]) {
        начало -= 1;
    }
    let mut конец = точка_проверки;
    while конец + 1 < символы.len() && является_частью_слова(символы[конец + 1]) {
        конец += 1;
    }

    Some(символы[начало..=конец].iter().collect())
}
