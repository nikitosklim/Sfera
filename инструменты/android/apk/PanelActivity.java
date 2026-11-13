package ru.sfera.panel;

import android.os.Bundle;
import java.io.File;
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
    }
}
