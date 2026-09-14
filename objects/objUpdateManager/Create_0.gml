
// Update source is this fork's GitHub releases, not upstream NordLandeW/DyNode.
#macro UPDATE_GITHUB_REPO "SlightlyLookAround/DyNode"
#macro UPDATE_RELEASES_LATEST ("https://api.github.com/repos/" + UPDATE_GITHUB_REPO + "/releases/latest")
#macro UPDATE_TARGET_FILE (program_directory + "update.zip")
#macro UPDATE_TEMP_DIR (program_directory + "tmp/")

// Event handles
_update_get_event_handle = undefined;
_update_download_event_handle = undefined;
_update_fetch_info_event_handle = undefined;
_update_unzip_event_handle = undefined;

_update_version = "";
_update_url = "";
_update_filename = "";
_update_github_url = "";
_update_github_body = "";
_update_changelog = "";

enum UPDATE_STATUS {
	IDLE,
	FETCH_INFO,		// update offered from GitHub release, waiting for user
	CHECKING_I,
	CHECKING_II,
	DOWNLOADING,
	UNZIP,
	READY,
	FAILED
};

/// @type {Enum.UPDATE_STATUS}
_update_status = UPDATE_STATUS.IDLE;

// For download progress bar
_update_received = 0;
_update_size = 0;

// Update functions
function update_cleanup() {
	var _status = DyCore_cleanup_tmpfiles(program_directory);
	if(_status < 0)
		show_debug_message("Cleanup error.");
}

function offer_update() {
	_update_changelog = _update_github_body;
	_update_status = UPDATE_STATUS.FETCH_INFO;

	announcement_play("[scale, 1.5]"+i18n_get("autoupdate_found_1")+"[#aed581]" + _update_version +
		"[/c][scale,1.2]\n[region,update_2][cycle,0,30]" + i18n_get("autoupdate_found_3") + "[/cycle][/region]\n" +
		"[/c][scale,1]\n[region,update][cycle,130,150]" + i18n_get("autoupdate_found_2") + "[/cycle][/region]" +
		"[/c][scale,0.8]\n[region,update_skip][c_white]" + i18n_get("autoupdate_found_4") + "[/cycle][/region]    " +
		"[/c][scale,0.8][region,update_off][c_ltgray]" + i18n_get("autoupdate_found_5") + "[/cycle][/region]\n\n" +
		"[c_ltgrey][scale, 1]"+format_markdown(_update_changelog)+"\n", 5000);
}

function start_fetch_info() {
	// Changelog and artifacts come from this fork's GitHub release only.
	offer_update();
}

function start_update() {
	if(_update_status != UPDATE_STATUS.FETCH_INFO) {
		show_debug_message("Update process error: invalid state.");
		return;
	}
	_update_status = UPDATE_STATUS.CHECKING_I;
	_update_download_event_handle = http_get_file(_update_github_url, UPDATE_TARGET_FILE);
	announcement_play("autoupdate_process_2");

	analytics_track_event("AutoUpdateStart", { version: _update_version });
}

function fallback_update() {
	// No upstream CDN fallback — retry the same GitHub release asset once.
	_update_status = UPDATE_STATUS.CHECKING_II;
	_update_download_event_handle = http_get_file(_update_github_url, UPDATE_TARGET_FILE);
	announcement_play("autoupdate_process_3");

	analytics_track_event("AutoUpdateFallback", { version: _update_version });
}

function start_update_unzip() {
	_update_status = UPDATE_STATUS.UNZIP;
	_update_unzip_event_handle = zip_unzip_async(UPDATE_TARGET_FILE, UPDATE_TEMP_DIR);
}

function update_ready() {
	_update_status = UPDATE_STATUS.READY;

	announcement_play("autoupdate_process_4");
	analytics_track_event("AutoUpdateReady", { version: _update_version });
}

function skip_update() {
	global.lastCheckedVersion = _update_version;

	announcement_play("autoupdate_skip");
	analytics_track_event("AutoUpdateSkip", { version: _update_version });
}

function stop_autoupdate() {
	if(global.autoupdate) {
		global.autoupdate = false;
		announcement_play("autoupdate_remove");
		analytics_track_event("AutoUpdateStop", { version: _update_version });
	}
}

// Check For Update
update_cleanup();
if(global.autoupdate)
	_update_get_event_handle = http_get(UPDATE_RELEASES_LATEST);
