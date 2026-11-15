package ru.sfera.panel;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import org.libsdl.app.SDLActivity;

/** Окно панели: SDL сам грузит библиотеки и вызывает SDL_main из libmain.so (код на Сфере). */
public class PanelActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] { "SDL2", "SDL2_ttf", "main" };
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // Запросы панели к сайту (каталог пакетов, вход, обновления) выполняет этот мост.
        NetBridge.start(new File(getFilesDir(), "net"));
        watchInstall();
    }

    /**
     * «Собрать APK» в панели кладёт собранное приложение в files/apps и создаёт files/net/install.req
     * с именем файла. Здесь оно передаётся системному установщику.
     */
    private void watchInstall() {
        final File req = new File(getFilesDir(), "net/install.req");
        Thread t = new Thread(new Runnable() {
            @Override public void run() {
                while (true) {
                    try {
                        if (req.exists()) {
                            final String name = new String(Files.readAllBytes(req.toPath()), StandardCharsets.UTF_8).trim();
                            req.delete();
                            runOnUiThread(new Runnable() {
                                @Override public void run() { install(name); }
                            });
                        }
                        Thread.sleep(300);
                    } catch (InterruptedException e) {
                        return;
                    } catch (Throwable ignore) {
                    }
                }
            }
        }, "sfera-install");
        t.setDaemon(true);
        t.start();
    }

    private void install(String name) {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW);
            i.setDataAndType(Uri.parse("content://ru.sfera.panel.apps/" + Uri.encode(name)), "application/vnd.android.package-archive");
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Throwable e) {
            try {
                Files.write(new File(getFilesDir(), "net/install.err").toPath(), String.valueOf(e).getBytes(StandardCharsets.UTF_8));
            } catch (Throwable ignore) {
            }
        }
    }
}
