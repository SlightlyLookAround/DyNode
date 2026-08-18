
// Release the cached beatline surface (created lazily in Draw_0).
if(surface_exists(beatlineSurf))
	surface_free(beatlineSurf);

timing_point_reset();
dyc_editor_set_ready(false);