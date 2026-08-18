
var nh = surface_get_height(application_surface);
if(nh <= 0) return;
var scalar = nh / BASE_RES_H;

// The credits block is fully static; render it once into a cached surface
// and blit it with an offset every frame. It is rebuilt only when the
// window size or the language changes (and freed in CleanUp).
if(!surface_exists(creditsSurf) || creditsScalar != scalar || creditsLang != i18n_get_lang()) {
    if(surface_exists(creditsSurf))
        surface_free(creditsSurf);

    creditsBlockH = render_credits_block(0, false);
    creditsSurf = surface_create(round(width * scalar), round(creditsBlockH * scalar));

    surface_set_target(creditsSurf);
        manually_set_view_size(width, creditsBlockH);
        draw_clear_alpha(c_black, 0);
        render_credits_block(0, true);
        manually_reset_view_size();
    surface_reset_target();

    creditsScalar = scalar;
    creditsLang = i18n_get_lang();
}

if(nowY + creditsBlockH < - 50) {
    nowY = height + 50;
    if(abs(baseSpeed - currentSpeed) < 10)
        currentLoopAcceleration = loopAcceleration;
}
else if(nowY > height + 50) {
    nowY = -creditsBlockH;
}

draw_surface_ext(creditsSurf, 0, nowY, 1/scalar, 1/scalar, 0, c_white, 1);

if(DEBUG_MODE) {
    var dbgText = $"nowY: {string_format(nowY, 0, 2)}\n";
    dbgText += $"currentAcceleration: {string_format(currentAcceleration, 0, 2)}\n";
    dbgText += $"currentSpeed: {string_format(currentSpeed, 0, 2)}\n";
    draw_set_color(c_red);
    draw_set_halign(fa_left);
    draw_text(10, 10, dbgText);
}