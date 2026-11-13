package ru.sfera.panel;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.List;
import java.util.Map;

/**
 * Сетевой мост для панели на Сфере (на телефоне нет curl).
 *
 * Панель кладёт в папку файл «<ид>.req» из трёх строк: метод, адрес, тело (для POST — «ключ=значение&...»).
 * Мост выполняет запрос и пишет «<ид>.out» (тело ответа), а затем «<ид>.code» (код ответа; 0 — нет связи).
 * Cookie сессии (sfera_sid) хранится в «cookie.txt» в той же папке — так вход помнится между запусками.
 */
public final class NetBridge {
    private final File dir;

    private NetBridge(File dir) {
        this.dir = dir;
    }

    public static void start(File dir) {
        dir.mkdirs();
        final NetBridge b = new NetBridge(dir);
        Thread t = new Thread(new Runnable() {
            @Override public void run() { b.loop(); }
        }, "sfera-net");
        t.setDaemon(true);
        t.start();
    }

    private void loop() {
        while (true) {
            try {
                File[] files = dir.listFiles();
                if (files != null) {
                    for (File f : files) {
                        if (f.getName().endsWith(".req")) {
                            handle(f);
                        }
                    }
                }
                Thread.sleep(120);
            } catch (InterruptedException e) {
                return;
            } catch (Throwable ignore) {
                // мост не должен падать из-за одного плохого запроса
            }
        }
    }

    private void handle(File req) {
        String name = req.getName();
        String id = name.substring(0, name.length() - 4);
        File running = new File(dir, id + ".run");
        if (!req.renameTo(running)) {
            return;
        }
        byte[] body = new byte[0];
        int code = 0;
        try {
            List<String> lines = Files.readAllLines(running.toPath(), StandardCharsets.UTF_8);
            String method = lines.size() > 0 ? lines.get(0).trim() : "GET";
            String address = lines.size() > 1 ? lines.get(1).trim() : "";
            String data = lines.size() > 2 ? lines.get(2) : "";
            HttpURLConnection c = (HttpURLConnection) new URL(address).openConnection();
            c.setConnectTimeout(15000);
            c.setReadTimeout(30000);
            c.setRequestMethod(method);
            c.setRequestProperty("X-Sfera", "1");
            c.setRequestProperty("User-Agent", "Sfera-Android");
            String cookie = readCookie();
            if (cookie.length() > 0) {
                c.setRequestProperty("Cookie", "sfera_sid=" + cookie);
            }
            if (method.equals("POST")) {
                c.setDoOutput(true);
                c.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");
                byte[] out = data.getBytes(StandardCharsets.UTF_8);
                c.setFixedLengthStreamingMode(out.length);
                OutputStream os = c.getOutputStream();
                os.write(out);
                os.close();
            }
            code = c.getResponseCode();
            InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
            if (in != null) {
                ByteArrayOutputStream buf = new ByteArrayOutputStream();
                byte[] chunk = new byte[8192];
                int n;
                while ((n = in.read(chunk)) > 0) {
                    buf.write(chunk, 0, n);
                }
                in.close();
                body = buf.toByteArray();
            }
            saveCookie(c.getHeaderFields());
            c.disconnect();
        } catch (Throwable e) {
            code = 0;
        }
        try {
            FileOutputStream fo = new FileOutputStream(new File(dir, id + ".out"));
            fo.write(body);
            fo.close();
            File tmp = new File(dir, id + ".code.tmp");
            FileOutputStream fc = new FileOutputStream(tmp);
            fc.write(Integer.toString(code).getBytes(StandardCharsets.UTF_8));
            fc.close();
            tmp.renameTo(new File(dir, id + ".code"));
        } catch (Throwable ignore) {
        }
        running.delete();
    }

    private String readCookie() {
        try {
            File f = new File(dir, "cookie.txt");
            if (f.exists()) {
                return new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8).trim();
            }
        } catch (Throwable ignore) {
        }
        return "";
    }

    private void saveCookie(Map<String, List<String>> headers) {
        List<String> set = headers.get("Set-Cookie");
        if (set == null) {
            return;
        }
        for (String line : set) {
            if (line.startsWith("sfera_sid=")) {
                String value = line.substring("sfera_sid=".length());
                int end = value.indexOf(';');
                if (end >= 0) {
                    value = value.substring(0, end);
                }
                File f = new File(dir, "cookie.txt");
                try {
                    if (value.length() == 0) {
                        f.delete();
                    } else {
                        FileOutputStream fo = new FileOutputStream(f);
                        fo.write(value.getBytes(StandardCharsets.UTF_8));
                        fo.close();
                    }
                } catch (Throwable ignore) {
                }
            }
        }
    }

    /** Для проверки на компьютере: java -cp . ru.sfera.panel.NetBridge <папка>. */
    public static void main(String[] args) throws Exception {
        start(new File(args[0]));
        Thread.sleep(Long.MAX_VALUE);
    }
}
