package ru.sfera.panel;

import org.libsdl.app.SDLActivity;

/** Окно панели: SDL сам грузит библиотеки и вызывает SDL_main из libmain.so (код на Сфере). */
public class PanelActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] { "SDL2", "SDL2_ttf", "main" };
    }
}
