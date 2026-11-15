package ru.sfera.app;

import org.libsdl.app.SDLActivity;

/** Окно приложения на Сфере: SDL грузит библиотеки и вызывает SDL_main из libmain.so (код пользователя). */
public class AppActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] { "SDL2", "SDL2_ttf", "main" };
    }
}
