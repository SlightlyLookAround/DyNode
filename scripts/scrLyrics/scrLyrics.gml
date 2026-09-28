/// Preview lyrics overlay (LRC / SRT).
/// Times are audio milliseconds (not chart timing points).

#macro LYRICS_DEFAULT_LAST_DURATION 3000
#macro LYRICS_DRAW_SCALE 1.0
#macro LYRICS_DRAW_SCALE_SUB 0.82

function lyrics_state() {
	if(!variable_global_exists("lyrics") || !is_struct(global.lyrics)) {
		global.lyrics = {
			loaded: false,
			path: "",
			source: "",
			offset: 0,
			cues: [],
			dual: false,
			status: 0 // 0=none, 1=ok, 2=fail (files present but unreadable)
		};
	}
	return global.lyrics;
}

function lyrics_clear() {
	var lyr = lyrics_state();
	lyr.loaded = false;
	lyr.path = "";
	lyr.source = "";
	lyr.offset = 0;
	lyr.cues = [];
	lyr.dual = false;
	lyr.status = 0;
}

/// True when at least one .lrc/.srt sits near the project/music.
function lyrics_files_present(_extraDir = "") {
	var _dirs = lyrics_collect_search_dirs(_extraDir);
	for(var _d = 0; _d < array_length(_dirs); _d++) {
		var _found = lyrics_list_files_in(_dirs[_d]);
		if(array_length(_found) > 0) return true;
	}
	return false;
}

/// Parse "mm:ss", "mm:ss.xx", "mm:ss:xxx", "hh:mm:ss,mmm" → ms. Returns -1 on failure.
function lyrics_parse_clock(_str) {
	_str = string_trim(_str);
	if(_str == "") return -1;

	var _m = regex_match_ext(_str, "^(\\d{1,3}):(\\d{1,2})(?:[\\.:,](\\d{1,3}))?$");
	if(is_array(_m) && array_length(_m) >= 3) {
		var _mm = real(_m[1]);
		var _ss = real(_m[2]);
		var _ms = 0;
		if(array_length(_m) > 3 && _m[3] != "") {
			var _frac = _m[3];
			if(string_length(_frac) == 1) _ms = real(_frac) * 100;
			else if(string_length(_frac) == 2) _ms = real(_frac) * 10;
			else _ms = real(_frac);
		}
		return _mm * 60000 + _ss * 1000 + _ms;
	}

	_m = regex_match_ext(_str, "^(\\d{1,2}):(\\d{1,2}):(\\d{1,2})(?:[\\.,](\\d{1,3}))?$");
	if(is_array(_m) && array_length(_m) >= 4) {
		var _hh = real(_m[1]);
		var _mm2 = real(_m[2]);
		var _ss2 = real(_m[3]);
		var _ms2 = 0;
		if(array_length(_m) > 4 && _m[4] != "") {
			var _frac2 = _m[4];
			if(string_length(_frac2) == 1) _ms2 = real(_frac2) * 100;
			else if(string_length(_frac2) == 2) _ms2 = real(_frac2) * 10;
			else _ms2 = real(_frac2);
		}
		return _hh * 3600000 + _mm2 * 60000 + _ss2 * 1000 + _ms2;
	}

	return -1;
}

/// Strip enhanced-LRC word tags like <00:10.00>.
function lyrics_strip_word_tags(_text) {
	var _result = "";
	var _i = 1;
	var _l = string_length(_text);
	while(_i <= _l) {
		var _ch = string_char_at(_text, _i);
		if(_ch == "<") {
			var _rest = string_copy(_text, _i, _l - _i + 1);
			var _close = string_pos(">", _rest);
			if(_close <= 0) {
				_result += _ch;
				_i += 1;
			} else {
				_i += _close;
			}
		} else {
			_result += _ch;
			_i += 1;
		}
	}
	return _result;
}

function lyrics_is_id_tag(_body) {
	// e.g. ar:xxx / ti:xxx / offset:12 / length:...
	var _p = string_pos(":", _body);
	if(_p <= 0) return false;
	var _key = string_lower(string_trim(string_copy(_body, 1, _p - 1)));
	switch(_key) {
		case "ar": case "al": case "ti": case "by": case "re":
		case "ve": case "length": case "offset":
			return true;
	}
	return false;
}

function lyrics_parse_offset_tag(_body) {
	var _p = string_pos(":", _body);
	if(_p <= 0) return 0;
	var _key = string_lower(string_trim(string_copy(_body, 1, _p - 1)));
	if(_key != "offset") return 0;
	var _val = string_trim(string_copy(_body, _p + 1, string_length(_body) - _p));
	if(_val == "") return 0;
	return real(_val);
}

/// Parse LRC text → cue array [{start,end,primary,secondary}] + offset.
function lyrics_parse_lrc(_text) {
	_text = string_replace_all(_text, "\r\n", "\n");
	_text = string_replace_all(_text, "\r", "\n");
	var _lines = string_split(_text, "\n");

	var _raw = []; // {t, text}
	var _offset = 0;

	for(var _li = 0; _li < array_length(_lines); _li++) {
		var _line = string_trim(_lines[_li]);
		if(_line == "") continue;

		// Collect leading [tags]
		var _times = [];
		var _ok = true;
		while(string_length(_line) >= 2 && string_char_at(_line, 1) == "[") {
			var _close = string_pos("]", _line);
			if(_close <= 1) {
				_ok = false;
				break;
			}
			var _body = string_copy(_line, 2, _close - 2);
			var _rest = string_copy(_line, _close + 1, string_length(_line) - _close);

			if(lyrics_is_id_tag(_body)) {
				_offset += lyrics_parse_offset_tag(_body);
				_line = string_trim(_rest);
				continue;
			}

			var _t = lyrics_parse_clock(_body);
			if(_t < 0) {
				_ok = false;
				break;
			}
			array_push(_times, _t);
			_line = string_trim(_rest);
		}

		if(!_ok || array_length(_times) == 0) continue;

		var _body_text = lyrics_strip_word_tags(_line);
		// Drop pure whitespace lyric body (timestamp-only markers still count as empty cues)
		for(var _ti = 0; _ti < array_length(_times); _ti++) {
			array_push(_raw, { t: _times[_ti], text: _body_text });
		}
	}

	// Sort by time (stable enough via simple insertion — lyric files are nearly sorted)
	for(var _i = 1; _i < array_length(_raw); _i++) {
		var _key = _raw[_i];
		var _j = _i - 1;
		while(_j >= 0 && _raw[_j].t > _key.t) {
			_raw[_j + 1] = _raw[_j];
			_j -= 1;
		}
		_raw[_j + 1] = _key;
	}

	// Merge same-timestamp lines into single/dual cues
	var _cues = [];
	var _k = 0;
	var _n = array_length(_raw);
	while(_k < _n) {
		var _t0 = _raw[_k].t;
		var _p = _raw[_k].text;
		var _s = "";
		var _used = 1;
		if(_k + 1 < _n && _raw[_k + 1].t == _t0) {
			_s = _raw[_k + 1].text;
			_used = 2;
		}
		array_push(_cues, {
			startTime: _t0,
			endTime: _t0 + LYRICS_DEFAULT_LAST_DURATION,
			primary: _p,
			secondary: _s
		});
		_k += _used;
	}

	// End = next start
	for(var _c = 0; _c < array_length(_cues) - 1; _c++) {
		_cues[_c].endTime = _cues[_c + 1].startTime;
	}

	return { cues: _cues, offset: _offset };
}

/// Parse SRT text → cue array + offset 0.
function lyrics_parse_srt(_text) {
	_text = string_replace_all(_text, "\r\n", "\n");
	_text = string_replace_all(_text, "\r", "\n");
	if(string_length(_text) > 0 && string_char_at(_text, string_length(_text)) != "\n")
		_text += "\n";

	var _lines = string_split(_text, "\n");
	var _cues = [];

	var _buf_p = "";
	var _buf_s = "";
	var _buf_start = -1;
	var _buf_end = -1;
	var _phase = 0; // 0 idle, 2 collecting text
	var _text_line_count = 0;

	for(var _li = 0; _li < array_length(_lines); _li++) {
		var _line = string_trim(_lines[_li]);

		// Flush on blank line
		if(_line == "") {
			if(_buf_start >= 0) {
				var _end0 = _buf_end;
				if(_end0 <= _buf_start) _end0 = _buf_start + LYRICS_DEFAULT_LAST_DURATION;
				array_push(_cues, {
					startTime: _buf_start,
					endTime: _end0,
					primary: _buf_p,
					secondary: _buf_s
				});
				_buf_p = "";
				_buf_s = "";
				_buf_start = -1;
				_buf_end = -1;
				_phase = 0;
				_text_line_count = 0;
			}
			continue;
		}

		// Time line (hh:mm:ss)
		var _tm = regex_match_ext(
			_line,
			"^(\\d{1,2}):(\\d{1,2}):(\\d{1,2})(?:[\\.,](\\d{1,3}))?\\s*-->\\s*(\\d{1,2}):(\\d{1,2}):(\\d{1,2})(?:[\\.,](\\d{1,3}))?$"
		);
		if(is_array(_tm) && array_length(_tm) >= 8) {
			if(_buf_start >= 0) {
				var _end1 = _buf_end;
				if(_end1 <= _buf_start) _end1 = _buf_start + LYRICS_DEFAULT_LAST_DURATION;
				array_push(_cues, {
					startTime: _buf_start,
					endTime: _end1,
					primary: _buf_p,
					secondary: _buf_s
				});
			}
			var _ms1 = (array_length(_tm) > 4 && _tm[4] != "") ? real(string_copy(_tm[4] + "000", 1, 3)) : 0;
			var _ms2 = (array_length(_tm) > 8 && _tm[8] != "") ? real(string_copy(_tm[8] + "000", 1, 3)) : 0;
			_buf_p = "";
			_buf_s = "";
			_buf_start = real(_tm[1]) * 3600000 + real(_tm[2]) * 60000 + real(_tm[3]) * 1000 + _ms1;
			_buf_end = real(_tm[5]) * 3600000 + real(_tm[6]) * 60000 + real(_tm[7]) * 1000 + _ms2;
			_phase = 2;
			_text_line_count = 0;
			continue;
		}

		// Compact SRT without hours: mm:ss,mmm --> mm:ss,mmm
		_tm = regex_match_ext(
			_line,
			"^(\\d{1,2}):(\\d{1,2})(?:[\\.,](\\d{1,3}))?\\s*-->\\s*(\\d{1,2}):(\\d{1,2})(?:[\\.,](\\d{1,3}))?$"
		);
		if(is_array(_tm) && array_length(_tm) >= 6) {
			if(_buf_start >= 0) {
				var _end2 = _buf_end;
				if(_end2 <= _buf_start) _end2 = _buf_start + LYRICS_DEFAULT_LAST_DURATION;
				array_push(_cues, {
					startTime: _buf_start,
					endTime: _end2,
					primary: _buf_p,
					secondary: _buf_s
				});
			}
			var _c1 = (array_length(_tm) > 3 && _tm[3] != "") ? real(string_copy(_tm[3] + "000", 1, 3)) : 0;
			var _c2 = (array_length(_tm) > 6 && _tm[6] != "") ? real(string_copy(_tm[6] + "000", 1, 3)) : 0;
			_buf_p = "";
			_buf_s = "";
			_buf_start = real(_tm[1]) * 60000 + real(_tm[2]) * 1000 + _c1;
			_buf_end = real(_tm[4]) * 60000 + real(_tm[5]) * 1000 + _c2;
			_phase = 2;
			_text_line_count = 0;
			continue;
		}

		// Bare index line while idle → skip
		if(_phase == 0 && regex_match(_line, "^\\d+$")) {
			continue;
		}

		// Text line
		if(_phase == 2) {
			var _body = lyrics_strip_word_tags(_line);
			if(_text_line_count == 0) {
				_buf_p = _body;
			} else if(_text_line_count == 1) {
				_buf_s = _body;
			} else {
				_buf_s += " " + _body;
			}
			_text_line_count += 1;
		}
	}

	// Final flush
	if(_buf_start >= 0) {
		var _endf = _buf_end;
		if(_endf <= _buf_start) _endf = _buf_start + LYRICS_DEFAULT_LAST_DURATION;
		array_push(_cues, {
			startTime: _buf_start,
			endTime: _endf,
			primary: _buf_p,
			secondary: _buf_s
		});
	}

	return { cues: _cues, offset: 0 };
}

function lyrics_read_text_file(_path) {
	if(!file_exists(_path)) return "";
	var _buf = buffer_load(_path);
	if(_buf < 0) return "";
	var _text = buffer_read(_buf, buffer_text);
	buffer_delete(_buf);
	// Strip UTF-8 BOM if present
	if(string_length(_text) > 0 && ord(string_char_at(_text, 1)) == 0xFEFF)
		_text = string_delete(_text, 1, 1);
	return _text;
}

function lyrics_parse_file(_path) {
	var _ext = string_lower(filename_ext(_path));
	var _text = lyrics_read_text_file(_path);
	if(_text == "") return undefined;

	if(_ext == ".lrc") {
		var _r = lyrics_parse_lrc(_text);
		return {
			cues: _r.cues,
			offset: _r.offset,
			source: "lrc",
			path: _path
		};
	}
	if(_ext == ".srt") {
		var _r2 = lyrics_parse_srt(_text);
		return {
			cues: _r2.cues,
			offset: _r2.offset,
			source: "srt",
			path: _path
		};
	}
	return undefined;
}

function lyrics_collect_search_dirs(_extraDir = "") {
	var _dirs = [];
	var _seen = {};

	if(_extraDir != "") {
		var _d0 = _extraDir;
		var _last0 = string_char_at(_d0, string_length(_d0));
		if(_last0 != "\\" && _last0 != "/") _d0 += "\\";
		var _key0 = string_lower(_d0);
		if(!variable_struct_exists(_seen, _key0)) {
			variable_struct_set(_seen, _key0, true);
			array_push(_dirs, _d0);
		}
	}

	var _proPath = "";
	if(instance_exists(objManager) && objManager.projectPath != "") {
		_proPath = objManager.projectPath;
		var _candidates = [
			filename_path(_proPath),
			filename_path(_proPath) + "lyrics\\",
			filename_path(_proPath) + "lyrics/",
			filename_path(_proPath) + "..\\lyrics\\"
		];
		for(var _ci = 0; _ci < array_length(_candidates); _ci++) {
			var _d = _candidates[_ci];
			if(_d == "") continue;
			var _last = string_char_at(_d, string_length(_d));
			if(_last != "\\" && _last != "/") _d += "\\";
			var _key = string_lower(_d);
			if(variable_struct_exists(_seen, _key)) continue;
			variable_struct_set(_seen, _key, true);
			array_push(_dirs, _d);
		}
	}

	var _mus = "";
	if(instance_exists(objManager) && objManager.musicPath != "") {
		_mus = objManager.musicPath;
		if(is_relative_path(_mus) && _proPath != "")
			_mus = get_absolute_path(filename_path(_proPath), _mus);
		var _md = filename_path(_mus);
		if(_md != "") {
			var _mlast = string_char_at(_md, string_length(_md));
			if(_mlast != "\\" && _mlast != "/") _md += "\\";
			var _mkey = string_lower(_md);
			if(!variable_struct_exists(_seen, _mkey)) {
				variable_struct_set(_seen, _mkey, true);
				array_push(_dirs, _md);
			}
		}
	}

	return _dirs;
}

function lyrics_list_files_in(_dir) {
	var _out = [];
	var _masks = ["*.lrc", "*.LRC", "*.srt", "*.SRT"];
	for(var _mi = 0; _mi < array_length(_masks); _mi++) {
		var _f = file_find_first(_dir + _masks[_mi], fa_none);
		while(_f != "") {
			array_push(_out, _dir + _f);
			_f = file_find_next();
		}
		file_find_close();
	}
	return _out;
}

function lyrics_basename(_path) {
	return string_lower(filename_name_no_ext(_path));
}

function lyrics_score_name(_path) {
	var _score = 0;
	var _name = string_lower(filename_name(_path));
	var _base = lyrics_basename(_path);

	var _musBase = "";
	if(instance_exists(objManager) && objManager.musicPath != "")
		_musBase = lyrics_basename(objManager.musicPath);
	var _proBase = "";
	if(instance_exists(objManager) && objManager.projectPath != "")
		_proBase = lyrics_basename(objManager.projectPath);
	var _title = "";
	if(instance_exists(objMain) && is_string(objMain.chartTitle))
		_title = string_lower(objMain.chartTitle);

	if(_musBase != "") {
		if(_base == _musBase) _score += 100;
		else if(string_pos(_musBase, _base) == 1) _score += 80;
		else if(string_pos(_musBase, _base) > 0) _score += 50;
	}
	if(_proBase != "" && _proBase != _musBase) {
		if(_base == _proBase) _score += 60;
		else if(string_pos(_proBase, _base) > 0) _score += 35;
	}
	if(_title != "" && string_pos(_title, _base) > 0) _score += 20;

	// Prefer bilingual / translation packs
	var _dualHints = ["translation", "translated", "covered", "bilingual", "dual", "双语", "翻译", "对照", "中英"];
	for(var _i = 0; _i < array_length(_dualHints); _i++) {
		if(string_pos(_dualHints[_i], _name) > 0) {
			_score += 25;
			break;
		}
	}
	// Slight penalty for "only" mono packs when alternatives exist
	if(string_pos("only", _name) > 0 || string_pos("eng_only", _name) > 0)
		_score -= 10;

	if(string_lower(filename_ext(_path)) == ".lrc") _score += 8;
	else _score += 5;

	return _score;
}

function lyrics_score_content(_parsed) {
	if(!is_struct(_parsed) || !is_array(_parsed.cues)) return -9999;
	var _score = 0;
	var _cues = _parsed.cues;
	var _n = array_length(_cues);
	if(_n == 0) return -9999;
	_score += min(_n, 80);
	var _dualCount = 0;
	for(var _i = 0; _i < _n; _i++) {
		if(_cues[_i].secondary != "") _dualCount += 1;
	}
	if(_dualCount > 0) _score += 40 + min(_dualCount, 40);
	return _score;
}

/// Discover and load the best lyric file near the project / music.
/// Returns 0 = no files, 1 = loaded, 2 = files present but load failed.
function lyrics_reload(_extraDir = "") {
	lyrics_clear();

	var _dirs = lyrics_collect_search_dirs(_extraDir);
	if(array_length(_dirs) == 0) return 0;

	// Deduplicate files
	var _files = [];
	var _seen = {};
	for(var _d = 0; _d < array_length(_dirs); _d++) {
		var _found = lyrics_list_files_in(_dirs[_d]);
		for(var _f = 0; _f < array_length(_found); _f++) {
			var _p = _found[_f];
			var _key = string_lower(_p);
			if(variable_struct_exists(_seen, _key)) continue;
			variable_struct_set(_seen, _key, true);
			array_push(_files, _p);
		}
	}
	if(array_length(_files) == 0) return 0;

	// Rank by name first, parse the promising ones, then finalize.
	var _ranked = [];
	for(var _i = 0; _i < array_length(_files); _i++) {
		array_push(_ranked, {
			path: _files[_i],
			nameScore: lyrics_score_name(_files[_i])
		});
	}
	// Insertion sort by nameScore desc
	for(var _a = 1; _a < array_length(_ranked); _a++) {
		var _key2 = _ranked[_a];
		var _b = _a - 1;
		while(_b >= 0 && _ranked[_b].nameScore < _key2.nameScore) {
			_ranked[_b + 1] = _ranked[_b];
			_b -= 1;
		}
		_ranked[_b + 1] = _key2;
	}

	var _best = undefined;
	var _bestScore = -9999;
	var _check = min(array_length(_ranked), 8); // parse at most top 8
	for(var _r = 0; _r < _check; _r++) {
		var _parsed = lyrics_parse_file(_ranked[_r].path);
		if(!is_struct(_parsed)) continue;
		var _cs = lyrics_score_content(_parsed);
		if(_cs <= -9999) continue;
		var _total = _ranked[_r].nameScore * 2 + _cs;
		if(_total > _bestScore) {
			_bestScore = _total;
			_best = _parsed;
		}
	}

	if(!is_struct(_best)) {
		lyrics_state().status = 2;
		return 2;
	}

	var lyr = lyrics_state();
	lyr.loaded = true;
	lyr.status = 1;
	lyr.path = _best.path;
	lyr.source = _best.source;
	lyr.offset = _best.offset;
	lyr.cues = _best.cues;
	lyr.dual = false;
	for(var _c = 0; _c < array_length(lyr.cues); _c++) {
		if(!is_string(lyr.cues[_c].primary)) lyr.cues[_c].primary = "";
		if(!is_string(lyr.cues[_c].secondary)) lyr.cues[_c].secondary = "";
		if(lyr.cues[_c].secondary != "") {
			lyr.dual = true;
			break;
		}
	}

	show_debug_message_safe($"Lyrics loaded: {lyr.path} ({array_length(lyr.cues)} cues, dual={lyr.dual})");
	return 1;
}

/// Toast after a project-open lyrics load (bottom-right announcement).
function lyrics_announce_load(_status) {
	if(_status == 1) {
		var lyr = lyrics_state();
		var _fmt = string_upper(lyr.source == "srt" ? "SRT" : "LRC");
		var _lines = i18n_get(lyr.dual ? "lyrics_line_dual" : "lyrics_line_single");
		announcement_play(i18n_get("anno_lyrics_loaded", [_fmt, _lines]), 4000, "lyrics_load");
	} else if(_status == 2) {
		announcement_warning("anno_lyrics_failed", 5000, "lyrics_load");
	}
}

function lyrics_get_cue(_time) {
	var lyr = lyrics_state();
	if(!lyr.loaded) return undefined;
	var _cues = lyr.cues;
	var _n = array_length(_cues);
	if(_n == 0) return undefined;

	var _t = _time + lyr.offset;
	// Binary search would be fine; linear is OK for typical lyric sizes.
	var _found = undefined;
	for(var _i = 0; _i < _n; _i++) {
		if(_cues[_i].startTime <= _t && _t < _cues[_i].endTime) {
			_found = _cues[_i];
			break;
		}
	}
	return _found;
}

function lyrics_make_text(_text, _role, _valign, _scale, _alp) {
	// Plain text only — lyric lines may contain '[' which scribble would treat as tags.
	return scribble(_text, "lyrics_" + _role + "_" + _text)
		.ignore_command_tags(true)
		.starting_format("sprMsdfNotoSans", c_white)
		.align(fa_center, _valign)
		.blend(c_white, _alp)
		.scale(_scale, _scale)
		.msdf_shadow(c_black, 0.55, 0, 2);
}

function lyrics_draw() {
	if(!variable_global_exists("lyricsEnabled") || !global.lyricsEnabled) return;
	if(!instance_exists(objMain)) return;

	var lyr = lyrics_state();
	if(!lyr.loaded) return;

	// Audio-synced time (ms). nowTime tracks FMOD playback / scrub position.
	var _cue = lyrics_get_cue(objMain.nowTime);
	if(!is_struct(_cue)) return;

	var _x = BASE_RES_W * 0.5;
	// Midpoint between the bottom judgment line and the window bottom edge.
	var _y = BASE_RES_H - objMain.targetLineBelow * 0.5;

	var _alpha = 1.0;
	// Soften slightly while the top-bar panel is open so UI stays readable.
	if(instance_exists(objTopBar) && objTopBar.active)
		_alpha = 0.35;

	var _primary = is_string(_cue.primary) ? _cue.primary : "";
	var _secondary = is_string(_cue.secondary) ? _cue.secondary : "";
	if(_primary == "" && _secondary == "") return;

	if(_secondary == "") {
		lyrics_make_text(_primary, "single", fa_middle, LYRICS_DRAW_SCALE, _alpha)
			.draw(_x, _y);
		return;
	}

	// Dual-line: center the whole two-line block on _y (original on top, translation below).
	var _gap = 4;
	var _h1 = 1;
	var _e1 = undefined;
	if(_primary != "") {
		_e1 = lyrics_make_text(_primary, "main", fa_top, LYRICS_DRAW_SCALE, _alpha);
		// get_height() is unscaled model height — apply the same scale used at draw.
		_h1 = max(_e1.get_height() * LYRICS_DRAW_SCALE, 1);
	}
	var _e2 = lyrics_make_text(_secondary, "sub", fa_top, LYRICS_DRAW_SCALE_SUB, _alpha * 0.9);
	var _h2 = max(_e2.get_height() * LYRICS_DRAW_SCALE_SUB, 1);
	var _total = ((_primary != "") ? (_h1 + _gap) : 0) + _h2;
	var _top = _y - _total * 0.5;

	if(_primary != "")
		_e1.draw(_x, _top);
	_e2.draw(_x, _top + ((_primary != "") ? (_h1 + _gap) : 0));
}
