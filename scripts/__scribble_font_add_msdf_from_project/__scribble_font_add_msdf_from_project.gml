// Feather disable all
function __scribble_font_add_msdf_from_project(_sprite)
{
    var _name = sprite_get_name(_sprite);
    
    static _font_data_map = __scribble_get_font_data_map();
    if (ds_map_exists(_font_data_map, _name))
    {
        __scribble_trace("Warning! An MSDF font for \"", _name, "\" has already been added. Destroying the old MSDF font and creating a new one");
        _font_data_map[? _name].__destroy();
    }
    
    var _scribble_state = __scribble_get_state();
    if (_scribble_state.__default_font == undefined)
    {
        if (SCRIBBLE_VERBOSE) __scribble_trace("Setting default font to \"" + string(_name) + "\"");
        _scribble_state.__default_font = _name;
    }
    
    var _is_krutidev = __scribble_asset_is_krutidev(_sprite, asset_sprite);
    var _global_glyph_bidi_map = __scribble_get_glyph_data().__bidi_map;
    
    if (SCRIBBLE_VERBOSE) __scribble_trace("Defined \"" + _name + "\" as an MSDF font");
    
    var _sprite_width  = sprite_get_width(_sprite);
    var _sprite_height = sprite_get_height(_sprite);
    var _sprite_uvs    = sprite_get_uvs(_sprite, 0);
    var _texture       = sprite_get_texture(_sprite, 0);
    
    //Correct for source sprites having their edges clipped off
    var _texel_w = texture_get_texel_width(_texture);
    var _texel_h = texture_get_texel_height(_texture);
    _sprite_uvs[0] -= _texel_w*_sprite_uvs[4];
    _sprite_uvs[1] -= _texel_h*_sprite_uvs[5];
    _sprite_uvs[2] += _texel_w*_sprite_width*(1 - _sprite_uvs[6]);
    _sprite_uvs[3] += _texel_h*_sprite_height*(1 - _sprite_uvs[7]);

    // [GMRT-WA-15767] GMRT 0.22 的贴图页上限是 2048，超过的图集会缩小打包（本项目的 MSDF 图集
    // 4096x8192 被缩成 1024x2048），但 sprite_get_uvs() 仍按原始尺寸返回 UV（这里 right=2.0、
    // bottom=4.0，且 texture_get_texel_width() 返回 0），于是 Scribble 算出的字形 UV 会偏大 4 倍，
    // 文字就糊成一片噪点。用 uvs[6]/uvs[7]（GMRT 给出的打包缩放系数）把 UV 换算回真实贴图范围。
    // GMS2/YYC 下 UV 正常（<=1），这段不会生效。
    // 说明与还原步骤见 notes/GMRT-15767-workaround.md。
    var _page_scale = 1;
    if ((_sprite_uvs[2] > 1 || _sprite_uvs[3] > 1) && _sprite_uvs[6] > 0 && _sprite_uvs[7] > 0)
    {
        _page_scale = _sprite_uvs[6];
        _sprite_uvs[0] *= _sprite_uvs[6];
        _sprite_uvs[1] *= _sprite_uvs[7];
        _sprite_uvs[2] *= _sprite_uvs[6];
        _sprite_uvs[3] *= _sprite_uvs[7];
    }
    
    var _font_directory = __scribble_get_font_directory();
    var _json_buffer = buffer_load(_font_directory + _name + ".json");
    
    if (_json_buffer < 0)
    {
        _json_buffer = buffer_load(_font_directory + _name);
    }
    
    if (_json_buffer < 0)
    {
        __scribble_error("Could not find \"", _font_directory + _name + ".json\"\nPlease add it to the project's Included Files");
    }
    
    var _json_string = buffer_read(_json_buffer, buffer_text);
    buffer_delete(_json_buffer);
    var _json = json_decode(_json_string); //TODO - Replace with json_parse()
    
    var _metrics_map     = _json[? "metrics"];
    var _json_glyph_list = _json[? "glyphs" ];
    var _atlas_map       = _json[? "atlas"  ];
    var _kerning_list    = _json[? "kerning"];
    
    var _em_size      = _atlas_map[? "size"         ];
    var _msdf_pxrange = _atlas_map[? "distanceRange"];

    // [GMRT-WA-15767] 图集现在按“每帧 <= 2044px”拆开存放（见 notes/GMRT-15767-workaround.md），
    // 这样 GMRT 打包贴图页时不会重采样 MSDF 数据。这里逐帧缓存（已做缩放修正的）UV 与纹理，
    // 下面每个字形再按自己在图集里的行号选帧。
    var _atlas_width  = _atlas_map[? "width" ];
    var _atlas_height = _atlas_map[? "height"];
    var _frame_count  = sprite_get_number(_sprite);
    var _frame_uvs    = array_create(_frame_count);
    var _frame_tex    = array_create(_frame_count);
    for (var _f = 0; _f < _frame_count; _f++)
    {
        var _frame_uv  = sprite_get_uvs(_sprite, _f);
        var _frame_tx  = sprite_get_texture(_sprite, _f);
        var _frame_tw  = texture_get_texel_width(_frame_tx);
        var _frame_th  = texture_get_texel_height(_frame_tx);
        _frame_uv[0] -= _frame_tw*_frame_uv[4];
        _frame_uv[1] -= _frame_th*_frame_uv[5];
        _frame_uv[2] += _frame_tw*_sprite_width *(1 - _frame_uv[6]);
        _frame_uv[3] += _frame_th*_sprite_height*(1 - _frame_uv[7]);
        if ((_frame_uv[2] > 1 || _frame_uv[3] > 1) && _frame_uv[6] > 0 && _frame_uv[7] > 0)
        {
            _frame_uv[0] *= _frame_uv[6];
            _frame_uv[1] *= _frame_uv[7];
            _frame_uv[2] *= _frame_uv[6];
            _frame_uv[3] *= _frame_uv[7];
        }
        _frame_uvs[_f] = _frame_uv;
        _frame_tex[_f] = _frame_tx;
    }
    
    var _json_line_height = _em_size*_metrics_map[? "lineHeight"];
    
    var _size = ds_list_size(_json_glyph_list);
    if (SCRIBBLE_VERBOSE) __scribble_trace("\"" + _name + "\" has " + string(_size) + " characters");
    
    var _font_data = new __scribble_class_font(_name, _size, true);
    _font_data.__runtime = true;
    
    var _font_glyphs_map      = _font_data.__glyphs_map;
    var _font_glyph_data_grid = _font_data.__glyph_data_grid;
    var _font_kerning_map     = _font_data.__kerning_map;
    if (_is_krutidev) _font_data.__is_krutidev = true;
    _font_data.__msdf_pxrange = _msdf_pxrange;
    
    var _i = 0;
    repeat(_size)
    {
        var _json_glyph_map = _json_glyph_list[| _i];
        var _plane_map = _json_glyph_map[? "planeBounds"];
        var _atlas_map = _json_glyph_map[? "atlasBounds"];
        
        var _unicode  = _json_glyph_map[? "unicode"];
        var _char = chr(_unicode);
        
        if (__SCRIBBLE_DEBUG) __scribble_trace("     Adding data for character \"" + string(_char) + "\" (" + string(_unicode) + ")");
        
        var _glyph_frame = 0;
        if (_atlas_map != undefined)
        {
            // [GMRT-WA-15767] 先在整张虚拟图集的坐标里定位，再折算到字形所在帧的局部坐标
            var _global_t  = _atlas_height - _atlas_map[? "top"   ]; //This atlas format is weird
            var _global_b  = _atlas_height - _atlas_map[? "bottom"];
            _glyph_frame   = floor(_global_t/_sprite_height);
            if (_glyph_frame < 0) _glyph_frame = 0;
            if (_glyph_frame >= _frame_count) _glyph_frame = _frame_count - 1;
            var _frame_off = _glyph_frame*_sprite_height;
            var _tex_l = _atlas_map[? "left"] + 1;
            var _tex_t = _global_t + 1 - _frame_off;
            var _tex_r = _atlas_map[? "right"] - 1;
            var _tex_b = _global_b - 1 - _frame_off;
        }
        else
        {
            var _tex_l = 0;
            var _tex_t = 0;
            var _tex_r = 0;
            var _tex_b = 0;
        }
        
        var _w = _tex_r - _tex_l;
        var _h = _tex_b - _tex_t;
        
        if (_plane_map != undefined)
        {
            var _xoffset  = _em_size*_plane_map[? "left"];
            var _yoffset  = _em_size - _em_size*_plane_map[? "top"]; //So, so weird
            var _xadvance = round(_em_size*_json_glyph_map[? "advance"]); //_w - _msdf_pxrange - round(_em_size*_plane_map[? "left"]);
        }
        else
        {
            var _xoffset  = 0;
            var _yoffset  = 0;
            var _xadvance = round(_em_size*_json_glyph_map[? "advance"]);
        }
        
        if (SCRIBBLE_MSDF_BORDER_TRIM > 0)
        {
            _tex_l += SCRIBBLE_MSDF_BORDER_TRIM;
            _tex_t += SCRIBBLE_MSDF_BORDER_TRIM;
            _tex_r -= SCRIBBLE_MSDF_BORDER_TRIM;
            _tex_b -= SCRIBBLE_MSDF_BORDER_TRIM;
            
            _w -= 2*SCRIBBLE_MSDF_BORDER_TRIM;
            _h -= 2*SCRIBBLE_MSDF_BORDER_TRIM;
            
            _xoffset += SCRIBBLE_MSDF_BORDER_TRIM;
            _yoffset += SCRIBBLE_MSDF_BORDER_TRIM;
        }
        
        //if (_xoffset < 0) __scribble_trace("char = ", _char, ", offset = ", _xoffset);
        
        if (__SCRIBBLE_DEBUG)
        {
            __scribble_trace(_char, "    ", _w, " x ", _h, ", advance=", _xadvance, ", dy=", _yoffset, ", diff=", _w - _xadvance);
            if (_plane_map != undefined)
            {
                __scribble_trace(_char, "    ", round(_em_size*(_plane_map[? "right"] - _plane_map[? "left"])));
                __scribble_trace(_char, "    ", _xadvance);
            }
        }
        
        var _glyph_uv = _frame_uvs[_glyph_frame];
        var _u0 = lerp(_glyph_uv[0], _glyph_uv[2], _tex_l/_sprite_width );
        var _v0 = lerp(_glyph_uv[1], _glyph_uv[3], _tex_t/_sprite_height);
        var _u1 = lerp(_glyph_uv[0], _glyph_uv[2], _tex_r/_sprite_width );
        var _v1 = lerp(_glyph_uv[1], _glyph_uv[3], _tex_b/_sprite_height);
        
        if ((_unicode >= 0x3000) && (_unicode <= 0x303F)) //CJK Symbols and Punctuation
        {
            var _bidi = __SCRIBBLE_BIDI.SYMBOL;
        }
        else if ((_unicode >= 0x3040) && (_unicode <= 0x30FF)) //Hiragana and Katakana
        {
            var _bidi = __SCRIBBLE_BIDI.ISOLATED_CJK;
        }
        else if ((_unicode >= 0x4E00) && (_unicode <= 0x9FFF)) //CJK Unified ideographs block
        {
            var _bidi = __SCRIBBLE_BIDI.ISOLATED_CJK;
        }
        else if ((_unicode >= 0xFF00) && (_unicode <= 0xFF0F)) //Fullwidth symbols
        {
            var _bidi = __SCRIBBLE_BIDI.SYMBOL;
        }
        else if ((_unicode >= 0xFF1A) && (_unicode <= 0xFF1F)) //More fullwidth symbols
        {
            var _bidi = __SCRIBBLE_BIDI.SYMBOL;
        }
        else if ((_unicode >= 0xFF5B) && (_unicode <= 0xFF64)) //Yet more fullwidth symbols
        {
            var _bidi = __SCRIBBLE_BIDI.SYMBOL;
        }
        else
        {
            var _bidi = _global_glyph_bidi_map[? _unicode];
            if (_bidi == undefined) _bidi = __SCRIBBLE_BIDI.L2R;
        }
        
        if (_is_krutidev)
        {
            if (_bidi != __SCRIBBLE_BIDI.WHITESPACE)
            {
                _bidi = __SCRIBBLE_BIDI.L2R_DEVANAGARI;
                _unicode += __SCRIBBLE_DEVANAGARI_OFFSET;
            }
        }
        
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.CHARACTER            ] = _char;
        
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.UNICODE              ] = _unicode;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.BIDI                 ] = _bidi;
                                                                        
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.X_OFFSET             ] = _xoffset;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.Y_OFFSET             ] = _yoffset;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.WIDTH                ] = _w;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.HEIGHT               ] = _h;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.FONT_HEIGHT          ] = _json_line_height;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.SEPARATION           ] = _xadvance;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.LEFT_OFFSET          ] = 1 - _xoffset - 0.5*_msdf_pxrange;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.FONT_SCALE           ] = 1;
        
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.TEXTURE              ] = _frame_tex[_glyph_frame];
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.U0                   ] = _u0;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.V0                   ] = _v0;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.U1                   ] = _u1;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.V1                   ] = _v1;
        
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.MSDF_PXRANGE         ] = _msdf_pxrange;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.MSDF_THICKNESS_OFFSET] = 0;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.BILINEAR             ] = true;
        
        _font_glyphs_map[? _unicode] = _i;
        
        ++_i;
    }
    
    //Guarantee we have a space character
    var _space_index = _font_glyphs_map[? 32];
    if (_space_index == undefined)
    {
        __scribble_trace("Warning! Space character not found in character set for MSDF font \"", _name, "\"");
        
        var _i = _size;
        ds_grid_resize(_font_glyph_data_grid, _i+1, SCRIBBLE_GLYPH.__SIZE);
        _font_glyphs_map[? 32] = _i;
        
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.CHARACTER            ] = " ";
        
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.UNICODE              ] = 0x20;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.BIDI                 ] = __SCRIBBLE_BIDI.WHITESPACE;
        
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.X_OFFSET             ] = 0;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.Y_OFFSET             ] = 0;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.WIDTH                ] = 0.5*_json_line_height;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.HEIGHT               ] = _json_line_height;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.FONT_HEIGHT          ] = _json_line_height;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.SEPARATION           ] = 0.5*_json_line_height;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.LEFT_OFFSET          ] = 0;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.FONT_SCALE           ] = 1;
        
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.TEXTURE              ] = _texture;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.U0                   ] = 0;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.V0                   ] = 0;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.U1                   ] = 0;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.V1                   ] = 0;
        
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.MSDF_PXRANGE         ] = undefined;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.MSDF_THICKNESS_OFFSET] = undefined;
        _font_glyph_data_grid[# _i, SCRIBBLE_GLYPH.BILINEAR             ] = undefined;
    }
    
    //And guarantee the space character is set up
    var _space_index = _font_glyphs_map[? 32];
    _font_glyph_data_grid[# _space_index, SCRIBBLE_GLYPH.WIDTH ] = _font_glyph_data_grid[# _space_index, SCRIBBLE_GLYPH.SEPARATION];
    _font_glyph_data_grid[# _space_index, SCRIBBLE_GLYPH.HEIGHT] = _json_line_height;
    
    if (SCRIBBLE_USE_KERNING)
    {
        var _i = 0;
        repeat(ds_list_size(_kerning_list))
        {
            var _kerning_pair = _kerning_list[| _i];
            var _offset = round(_em_size*_kerning_pair[? "advance"]);
            if (_offset != 0) _font_kerning_map[? ((_kerning_pair[? "unicode2"] & 0xFFFF) << 16) | (_kerning_pair[? "unicode1"] & 0xFFFF)] = _offset;
            ++_i;
        }
    }
    
    ds_map_destroy(_json);
    
    _font_data.__calculate_font_height();
}
