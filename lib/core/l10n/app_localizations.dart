import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String get(String key) =>
      _localizedStrings[locale.languageCode]?[key] ??
      _localizedStrings['en']![key] ??
      key;

  /// Lookup without [BuildContext] (voice pipeline, services). Falls back to English.
  static String lookup(String languageCode, String key) {
    final lc = languageCode.toLowerCase();
    return _localizedStrings[lc]?[key] ??
        _localizedStrings['en']![key] ??
        key;
  }

  String get appName => get('app_name');
  String get profileTitle => get('profile_title');
  String get language => get('language');
  String get saveMedicalProfile => get('save_medical_profile');
  String get criticalMedicalInfo => get('critical_medical_info');
  String get emergencyContacts => get('emergency_contacts');
  String get goldenHourDetails => get('golden_hour_details');
  String get sosLock => get('sos_lock');
  String get topLifeSavers => get('top_life_savers');
  String get livesSaved => get('lives_saved');
  String get activeAlerts => get('active_alerts');
  String get rank => get('rank');
  String get onDuty => get('on_duty');
  String get standby => get('standby');
  String get sosButton => get('sos');
  String get callNow => get('call_now');
  String get quickGuide => get('quick_guide');
  String get detailedInstructions => get('detailed_instructions');
  String get redFlags => get('red_flags');
  String get cautions => get('cautions');
  String get voiceWalkthrough => get('voice_walkthrough');
  String get playing => get('playing');
  String get swipeNextGuide => get('swipe_next_guide');
  String get watchVideoGuide => get('watch_video_guide');
  String get emergencyGridScan => get('emergency_grid_scan');
  String get areaTelemetry => get('area_telemetry');
  String get reportHazard => get('report_hazard');
  String get todaysDuty => get('todays_duty');
  String get bloodType => get('blood_type');
  String get allergies => get('allergies');
  String get medicalConditions => get('medical_conditions');
  String get contactName => get('contact_name');
  String get contactPhone => get('contact_phone');
  String get contactEmail => get('contact_email');
  String get relationship => get('relationship');
  String get medications => get('medications');
  String get organDonor => get('organ_donor');
  String get goodMorning => get('good_morning');
  String get goodAfternoon => get('good_afternoon');
  String get goodEvening => get('good_evening');
  String get hospitals => get('hospitals');
  String get visualWalkthrough => get('visual_walkthrough');
  String get lifeline => get('lifeline');
  String get navHome => get('nav_home');
  String get navMap => get('nav_map');
  String get navGrid => get('nav_grid');
  String get navProfile => get('nav_profile');
  String mapCachingOfflinePct(int pct) =>
      get('map_caching_offline_pct').replaceAll('{pct}', '$pct');
  String get mapDrillPracticeBanner => get('map_drill_practice_banner');
  String get mapRecenterTooltip => get('map_recenter_tooltip');
  String get mapLegendHospital => get('map_legend_hospital');
  String get mapLegendLiveSosHistory => get('map_legend_live_sos_history');
  String get mapLegendPastThisHex => get('map_legend_past_this_hex');
  String mapLegendIncidentsInArea(int n) =>
      get('map_legend_in_area').replaceAll('{n}', '$n');
  String mapLegendIncidentsInCell(int n) =>
      get('map_legend_in_cell').replaceAll('{n}', '$n');
  String get mapLegendVolunteersOnDuty => get('map_legend_volunteers_on_duty');
  String mapLegendVolunteersInGrid(int n) =>
      get('map_legend_volunteers_in_grid').replaceAll('{n}', '$n');
  String get mapLegendResponderScene => get('map_legend_responder_scene');
  String mapResponderRoutes(int n) => (n == 1
          ? get('map_responder_routes_one')
          : get('map_responder_routes_many'))
      .replaceAll('{n}', '$n');
  String get mapFiltersTitle => get('map_filters_title');
  String get volunteerActiveBrowserLocationOff =>
      get('volunteer_active_browser_location_off');
  String get volunteerActiveLocationRequired =>
      get('volunteer_active_location_required');
  String volunteerActiveMapLoadFailed(String detail) =>
      get('volunteer_active_map_load_failed').replaceAll('{detail}', detail);
  String get volunteerActiveNoMapCoords => get('volunteer_active_no_map_coords');
  String get volunteerActiveGpsUnavailable =>
      get('volunteer_active_gps_unavailable');
  String get volunteerActiveOfflineQrTitle =>
      get('volunteer_active_offline_qr_title');
  String get volunteerActiveOfflineQrBody =>
      get('volunteer_active_offline_qr_body');
  String get volunteerActiveClose => get('volunteer_active_close');
  String get volunteerActiveDispatchedServices =>
      get('volunteer_active_dispatched_services');
  String get volunteerActiveAmbulance => get('volunteer_active_ambulance');
  String get volunteerActiveOnScene => get('volunteer_active_on_scene');
  String get volunteerActiveEnRoute => get('volunteer_active_en_route');
  String get volunteerActiveExitTitle => get('volunteer_active_exit_title');
  String get volunteerActiveLeaveVictim => get('volunteer_active_leave_victim');
  String get volunteerActiveLeaveVolunteer =>
      get('volunteer_active_leave_volunteer');
  String get volunteerActiveStay => get('volunteer_active_stay');
  String get volunteerActiveExit => get('volunteer_active_exit');
  String get volunteerActiveSosExpired => get('volunteer_active_sos_expired');
  String get volunteerActiveBackToResponse =>
      get('volunteer_active_back_to_response');
  String get volunteerActiveOfflineQrAccess =>
      get('volunteer_active_offline_qr_access');
  String get volunteerActiveHospitalEvLabel =>
      get('volunteer_active_hospital_ev_label');
  String get volunteerActiveHospitalEvSubtitle =>
      get('volunteer_active_hospital_ev_subtitle');
  String get volunteerActiveNearbyHospitalsMaps =>
      get('volunteer_active_nearby_hospitals_maps');
  String get volunteerActiveChecklistSaved =>
      get('volunteer_active_checklist_saved');
  String volunteerActiveSaveFailed(String detail) =>
      get('volunteer_active_save_failed').replaceAll('{detail}', detail);
  String get volunteerActivePhotoLimit => get('volunteer_active_photo_limit');
  String volunteerActivePhotoError(String detail) =>
      get('volunteer_active_photo_error').replaceAll('{detail}', detail);
  String get volunteerActiveVictimLoading =>
      get('volunteer_active_victim_loading');
  String get sosActiveUpdateSentLivekit => get('sos_active_update_sent_livekit');
  String get sosActiveUpdateSentChannel => get('sos_active_update_sent_channel');
  String get sosActiveCouldNotSendUpdate =>
      get('sos_active_could_not_send_update');
  String get sosActiveVoiceTextSent => get('sos_active_voice_text_sent');
  String get sosActiveCouldNotSendVoice => get('sos_active_could_not_send_voice');
  String get sosActiveVoiceUpdateSent => get('sos_active_voice_update_sent');
  String get sosActiveVoiceRecordFailed => get('sos_active_voice_record_failed');
  String get sosActiveRoutesToYou => get('sos_active_routes_to_you');
  String get sosActiveAvgResponseTime => get('sos_active_avg_response_time');
  String get sosActiveRecentVolume => get('sos_active_recent_volume');
  String get sosActiveCongestionWarning => get('sos_active_congestion_warning');
  String get stepPrefix => get('step_prefix');
  String get highlightsSteps => get('highlights_steps');
  String get offlineMode => get('offline_mode');
  String get volunteer => get('volunteer');
  String get unranked => get('unranked');
  String get live => get('live');
  String get you => get('you');
  String get saved => get('saved');
  String get xpResponses => get('xp_responses');
  String get dutyMonitoring => get('duty_monitoring');
  String get turnOnDutyMsg => get('turn_on_duty_msg');
  String get onDutySnack => get('on_duty_snack');
  String get offDutySnack => get('off_duty_snack');
  String get nearbyVolunteersLocating => get('nearby_volunteers_locating');
  String get activeVolunteersGridNone => get('active_volunteers_grid_none');
  String activeVolunteersGridCount(int n) {
    if (n <= 0) return activeVolunteersGridNone;
    return get('active_volunteers_grid').replaceAll('{n}', '$n');
  }

  String get leaderboardOffline => get('leaderboard_offline');
  String get leaderboardOfflineSub => get('leaderboard_offline_sub');
  String get leaderboardEmptyPrimary => get('leaderboard_empty_primary');
  String get leaderboardEmptySecondary => get('leaderboard_empty_secondary');
  String get leaderboardOnDutyFallbackTitle => get('leaderboard_on_duty_fallback_title');
  String get leaderboardOnDutyStat => get('leaderboard_on_duty_stat');
  String get leaderboardViewGrid => get('leaderboard_view_grid');
  String get leaderboardSoloOnDuty => get('leaderboard_solo_on_duty');
  String get setSosPinFirst => get('set_sos_pin_first');
  String get setPinSafetyMsg => get('set_pin_safety_msg');
  String get setPinNow => get('set_pin_now');
  String get later => get('later');

  // Emergency consent
  String get emergencyConsentTitle => get('emergency_consent_title');
  String get emergencyConsentBody => get('emergency_consent_body');
  String get consentNotNow => get('consent_not_now');
  String get consentContinue => get('consent_continue');

  // SOS screen
  String get sosScreenTitle => get('sos_screen_title');
  String get sosHoldBanner => get('sos_hold_banner');
  String get sosHoldButton => get('sos_hold_button');
  String get sosOfflineQueued => get('sos_offline_queued');
  String get sosSemanticsHoldHint => get('sos_semantics_hold_hint');
  String get sosStarting => get('sos_starting');
  String get sosReleaseToSend => get('sos_release_to_send');
  String get sosReleaseCancel => get('sos_release_cancel');
  String get sosCheckConnectionRetry => get('sos_check_connection_retry');
  String get sosRetry => get('sos_retry');
  String get sosActiveFlowFailed => get('sos_active_flow_failed');
  String get sosPinDispatchBody => get('sos_pin_dispatch_body');
  String sosFailedMessage(String detail) =>
      get('sos_failed_prefix').replaceAll('{detail}', detail);

  // Volunteer voice mode prompt
  String get volunteerVoiceModeTitle => get('volunteer_voice_mode_title');
  String get volunteerVoiceModeSubtitle => get('volunteer_voice_mode_subtitle');
  String get volunteerVoiceModeAudioTitle =>
      get('volunteer_voice_mode_audio_title');
  String get volunteerVoiceModeAudioSubtitle =>
      get('volunteer_voice_mode_audio_subtitle');
  String get volunteerVoiceModeSilentTitle =>
      get('volunteer_voice_mode_silent_title');
  String get volunteerVoiceModeSilentSubtitle =>
      get('volunteer_voice_mode_silent_subtitle');
  String get volunteerVoiceModeFooter =>
      get('volunteer_voice_mode_footer');

  // Common actions
  String get cancel => get('cancel');
  String get save => get('save');

  // PIN dialog
  String get pinChangeTitle => get('pin_change_title');
  String get pinSetTitle => get('pin_set_title');
  String get pinHintNew => get('pin_hint_new');
  String get pinHintConfirm => get('pin_hint_confirm');
  String get pinErrorTooShort => get('pin_error_too_short');
  String get pinErrorMismatch => get('pin_error_mismatch');

  // Profile sync & messages
  String get profileSynced => get('profile_synced');
  String get profileNotSynced => get('profile_not_synced');
  String get profileSaving => get('profile_saving');
  String get profileQueuedOffline => get('profile_queued_offline');
  String get profileSaveFailed => get('profile_save_failed');
  String get profileSaveTimedOut => get('profile_save_timed_out');
  String get profileTimeJustNow => get('profile_time_just_now');
  String profileTimeMinAgo(int n) =>
      get('profile_time_min_ago').replaceAll('{n}', '$n');
  String profileTimeHoursAgo(int n) =>
      get('profile_time_hours_ago').replaceAll('{n}', '$n');
  String profileTimeDaysAgo(int n) =>
      get('profile_time_days_ago').replaceAll('{n}', '$n');
  String get profileDbUnreachable => get('profile_db_unreachable');
  String get profileSavedOfflineMsg => get('profile_saved_offline_msg');
  String get profileSavedMsg => get('profile_saved_msg');
  String get profileSaveTimeoutMsg => get('profile_save_timeout_msg');
  String profileSaveError(String e) =>
      get('profile_save_error').replaceAll('{e}', e);
  String get profilePinSavedOffline => get('profile_pin_saved_offline');
  String get profilePinSaved => get('profile_pin_saved');
  String profilePinSaveError(String e) =>
      get('profile_pin_save_error').replaceAll('{e}', e);

  String get drillProfileBanner => get('drill_profile_banner');
  String get profileSmsContactTitle => get('profile_sms_contact_title');
  String get profileSmsContactSubtitle => get('profile_sms_contact_subtitle');
  String get profileDispatchDeskTitle => get('profile_dispatch_desk_title');
  String get profileDispatchDeskSubtitle => get('profile_dispatch_desk_subtitle');
  String get profilePinStatusSet => get('profile_pin_status_set');
  String get profilePinStatusUnset => get('profile_pin_status_unset');
  String get profileChangePinBtn => get('profile_change_pin_btn');
  String get profileSetPinBtn => get('profile_set_pin_btn');
  String get profilePinExitNote => get('profile_pin_exit_note');
  String get profileSosPinTitle => get('profile_sos_pin_title');
  String get profileVoiceAgentEnableTitle => get('profile_voice_agent_enable_title');
  String get profileVoiceAgentEnableSubtitle => get('profile_voice_agent_enable_subtitle');
  String get profileVoiceStartMutedTitle => get('profile_voice_start_muted_title');
  String get profileVoiceStartMutedSubtitle => get('profile_voice_start_muted_subtitle');
  String get profileVoiceWalkthroughTitle => get('profile_voice_walkthrough_title');
  String get profileVoiceWalkthroughSubtitle => get('profile_voice_walkthrough_subtitle');

  String get profileUnsavedTitle => get('profile_unsaved_title');
  String get profileUnsavedBody => get('profile_unsaved_body');
  String get profileStay => get('profile_stay');
  String get profileDiscard => get('profile_discard');
  String get profileAdditionalInfo => get('profile_additional_info');
  String get profilePronounsTitle => get('profile_pronouns_title');
  String get profilePronounsHeHim => get('profile_pronouns_he_him');
  String get profilePronounsSheHer => get('profile_pronouns_she_her');
  String get profilePronounsTheyThem => get('profile_pronouns_they_them');

  String get profileTabVolunteerHub => get('profile_tab_volunteer_hub');
  String get profileVolunteerCertificationsTitle => get('profile_volunteer_certifications_title');
  String get profileVolunteerCertificationsSubtitle => get('profile_volunteer_certifications_subtitle');
  String get profileCprCertifiedTitle => get('profile_cpr_certified_title');
  String get profileCprCertifiedSubtitle => get('profile_cpr_certified_subtitle');
  String get profileAedCertifiedTitle => get('profile_aed_certified_title');
  String get profileAedCertifiedSubtitle => get('profile_aed_certified_subtitle');
  String get profileCertUploading => get('profile_cert_uploading');
  String get profileUploadCprCert => get('profile_upload_cpr_cert');
  String get profileUploadAedCert => get('profile_upload_aed_cert');
  String get profileCertUploadNoBytes => get('profile_cert_upload_no_bytes');
  String get profileCertUploaded => get('profile_cert_uploaded');
  String profileCertUploadFailed(String e) =>
      get('profile_cert_upload_failed').replaceAll('{e}', e);
  String get help => get('help_screen_title');
  String get profileStatNever => get('profile_stat_never');
  String get profileLoading => get('profile_loading');
  String get profileError => get('profile_error');
  String get profileVolunteerStatsTitle => get('profile_volunteer_stats_title');
  String get profileStatIncidentsResponded => get('profile_stat_incidents_responded');
  String get profileStatTotalLivesSaved => get('profile_stat_total_lives_saved');
  String get profileStatLastIncident => get('profile_stat_last_incident');
  String get profileStatValueCreated => get('profile_stat_value_created');
  String get profileStatValueCreatedHint => get('profile_stat_value_created_hint');

  String get profileHintBloodType => get('profile_hint_blood_type');
  String get profileHintAllergies => get('profile_hint_allergies');
  String get profileHintConditions => get('profile_hint_conditions');
  String get profileHintContactName => get('profile_hint_contact_name');
  String get profileHintRelationship => get('profile_hint_relationship');
  String get profileHintPhone => get('profile_hint_phone');
  String get profileHintContactEmail => get('profile_hint_contact_email');
  String get profileHintMedications => get('profile_hint_medications');
  String get profileHintDonor => get('profile_hint_donor');

  // Home & quick SOS
  String get homeDutyHeading => get('home_duty_heading');
  String homeDutyProgress(int done, int total) =>
      get('home_duty_progress').replaceAll('{done}', '$done').replaceAll('{total}', '$total');
  String get homeMapSemantics => get('home_map_semantics');
  String get homeRecenterMap => get('home_recenter_map');
  String get homeSosLargeFabHint => get('home_sos_large_fab_hint');
  String get homeSosCancelledSnack => get('home_sos_cancelled_snack');
  String get homeSosSentSnack => get('home_sos_sent_snack');
  String get quickSosTitle => get('quick_sos_title');
  String get quickSosSubtitle => get('quick_sos_subtitle');
  String get quickSosPracticeBanner => get('quick_sos_practice_banner');
  String get quickSosSectionWhat => get('quick_sos_section_what');
  String get quickSosSectionSomeoneElse => get('quick_sos_section_someone_else');
  String get quickSosSendNow => get('quick_sos_send_now');
  String get quickSosSelectFirst => get('quick_sos_select_first');
  String get quickSosSectionVictim => get('quick_sos_section_victim');
  String get quickSosVictimSubtitle => get('quick_sos_victim_subtitle');
  String get quickSosSectionPeople => get('quick_sos_section_people');
  String get quickSosYesSomeoneElse => get('quick_sos_yes_someone_else');
  String get quickSosNoForMe => get('quick_sos_no_for_me');
  String get quickSosOtherHint => get('quick_sos_other_hint');
  String get quickSosClose => get('quick_sos_close');
  String get quickSosDrillSubmitDisabled => get('quick_sos_drill_submit_disabled');
  String quickSosFailed(String detail) =>
      get('quick_sos_failed').replaceAll('{detail}', detail);
  String get quickSosCouldNotStart => get('quick_sos_could_not_start');
  String get quickSosVictimConsciousQ => get('quick_sos_victim_conscious_q');
  String get quickSosVictimBreathingQ => get('quick_sos_victim_breathing_q');
  String get quickSosLabelYes => get('quick_sos_label_yes');
  String get quickSosLabelNo => get('quick_sos_label_no');
  String get quickSosLabelUnsure => get('quick_sos_label_unsure');
  String get quickSosPerson => get('quick_sos_person');
  String get quickSosPeople => get('quick_sos_people');
  String get quickSosPeopleThreePlus => get('quick_sos_people_three_plus');

  String get loginTagline => get('login_tagline');
  String get loginSubtitle => get('login_subtitle');
  String get loginContinueGoogle => get('login_continue_google');
  String get loginContinuePhone => get('login_continue_phone');
  String get loginSendCode => get('login_send_code');
  String get loginVerifyLogin => get('login_verify_login');
  String get loginPhoneLabel => get('login_phone_label');
  String get loginPhoneHint => get('login_phone_hint');
  String get loginOtpLabel => get('login_otp_label');
  String get loginBackOptions => get('login_back_options');
  String get loginChangePhone => get('login_change_phone');
  String get loginDrillMode => get('login_drill_mode');
  String get loginDrillSubtitle => get('login_drill_subtitle');
  String get loginDrillSemantics => get('login_drill_semantics');
  String get loginPractiseVictim => get('login_practise_victim');
  String get loginPractiseVolunteer => get('login_practise_volunteer');
  String get loginAdminNote => get('login_admin_note');
  String get loginEmsDashboard => get('login_ems_dashboard');
  String get loginEmergencyOperator => get('login_emergency_operator');

  String get aiAssistPracticeBanner => get('ai_assist_practice_banner');
  String aiAssistRailSemantics(int n, String title) =>
      get('ai_assist_rail_semantics').replaceAll('{n}', '$n').replaceAll('{title}', title);
  String get aiAssistEmergencyToggleOn => get('ai_assist_emergency_toggle_on');
  String get aiAssistEmergencyToggleOff => get('ai_assist_emergency_toggle_off');

  String get dashboardExitDrillTitle => get('dashboard_exit_drill_title');
  String get dashboardExitDrillBody => get('dashboard_exit_drill_body');
  String get dashboardBackLoginTooltip => get('dashboard_back_login_tooltip');
  String get dashboardExitDrillConfirm => get('dashboard_exit_drill_confirm');

  static const Map<String, Map<String, String>> _localizedStrings = {
    // ── English ─────────────────────────────────────────────────────────────
    'en': {
      'app_name': 'EmergencyOS',
      'profile_title': 'Profile & Medical ID',
      'language': 'Language',
      'save_medical_profile': 'Save Medical Profile',
      'critical_medical_info': 'Critical Medical Info',
      'emergency_contacts': 'Emergency Contacts',
      'golden_hour_details': 'Golden Hour Details',
      'sos_lock': 'SOS Lock',
      'top_life_savers': 'Top Life Savers',
      'lives_saved': 'Lives Saved',
      'active_alerts': 'Active Alerts',
      'rank': 'Rank',
      'on_duty': 'ON DUTY',
      'standby': 'STANDBY',
      'sos': 'SOS',
      'call_now': 'CALL NOW',
      'quick_guide': 'QUICK GUIDE',
      'detailed_instructions': 'DETAILED INSTRUCTIONS',
      'red_flags': 'RED FLAGS',
      'cautions': 'CAUTIONS',
      'voice_walkthrough': 'Voice walkthrough',
      'playing': 'Playing...',
      'swipe_next_guide': 'Swipe for next guide',
      'watch_video_guide': 'Watch full video guide',
      'emergency_grid_scan': 'EMERGENCY GRID SCAN',
      'area_telemetry': 'Area Telemetry & Risk Index',
      'report_hazard': 'Report Hazard',
      'todays_duty': "Today's Duty",
      'blood_type': 'Blood Type',
      'allergies': 'Allergies',
      'medical_conditions': 'Medical Conditions',
      'contact_name': 'Primary Contact Name',
      'contact_phone': 'Primary Contact Phone',
      'contact_email': 'Primary Contact Email',
      'relationship': 'Relationship',
      'medications': 'Current Medications',
      'organ_donor': 'Organ Donor Status',
      'good_morning': 'Good Morning,',
      'good_afternoon': 'Good Afternoon,',
      'good_evening': 'Good Evening,',
      'hospitals': 'Hospitals / Trauma',
      'visual_walkthrough': 'Visual walkthrough',
      'lifeline': 'Lifeline',
      'nav_home': 'Home',
      'nav_map': 'Map',
      'nav_grid': 'Grid',
      'nav_profile': 'Profile',
      'map_caching_offline_pct': 'Caching area for offline — {pct}%',
      'map_drill_practice_banner':
          'Practice Grid: pulsing pins = demo active alerts. Use Map filters for layers — not real data.',
      'map_recenter_tooltip': 'Re-center',
      'map_legend_hospital': 'Hospital',
      'map_legend_live_sos_history': 'Live SOS / history',
      'map_legend_past_this_hex': 'Past (this hex)',
      'map_legend_in_area': '{n} in area',
      'map_legend_in_cell': '{n} in cell',
      'map_legend_volunteers_on_duty': 'Volunteers on duty',
      'map_legend_volunteers_in_grid': '{n} in grid',
      'map_legend_responder_scene': 'Responder → scene',
      'map_responder_routes_one': '{n} route',
      'map_responder_routes_many': '{n} routes',
      'map_filters_title': 'Map filters',
      'volunteer_active_browser_location_off':
          'Browser location is off or blocked. You can still view the incident map — enable location in the site settings to show your position.',
      'volunteer_active_location_required':
          'Location permission is required for this consignment.',
      'volunteer_active_map_load_failed': 'Could not load consignment map. {detail}',
      'volunteer_active_no_map_coords':
          'This incident has no map coordinates. Cannot open consignment.',
      'volunteer_active_gps_unavailable':
          'Could not read your GPS yet. Open again outdoors or enable precise location.',
      'volunteer_active_offline_qr_title': 'Offline Location QR',
      'volunteer_active_offline_qr_body':
          'Scan to share incident location access offline.',
      'volunteer_active_close': 'Close',
      'volunteer_active_dispatched_services': 'Dispatched Services',
      'volunteer_active_ambulance': 'Ambulance',
      'volunteer_active_on_scene': 'On Scene',
      'volunteer_active_en_route': 'En Route',
      'volunteer_active_exit_title': 'Exit response window?',
      'volunteer_active_leave_victim': 'Leave this incident view?',
      'volunteer_active_leave_volunteer':
          'You will stop responding to this incident. Your assignment is cleared so the app will not send you back here automatically.',
      'volunteer_active_stay': 'Stay',
      'volunteer_active_exit': 'Exit',
      'volunteer_active_sos_expired':
          'This SOS has expired (1 hour) and was archived.',
      'volunteer_active_back_to_response': 'Back to response',
      'volunteer_active_offline_qr_access': 'Offline QR Access',
      'volunteer_active_hospital_ev_label': 'Hospital & emergency vehicles',
      'volunteer_active_hospital_ev_subtitle':
          'Routed estimates are written to this incident as you approach. Open Maps for real facilities near the pin.',
      'volunteer_active_nearby_hospitals_maps': 'Nearby hospitals in Google Maps',
      'volunteer_active_checklist_saved':
          'Scene checklist saved for dispatch and other responders.',
      'volunteer_active_save_failed': 'Could not save: {detail}',
      'volunteer_active_photo_limit': 'You can upload up to 3 scene photos.',
      'volunteer_active_photo_error': 'Photo error: {detail}',
      'volunteer_active_victim_loading': 'Victim info loading…',
      'sos_active_update_sent_livekit': 'Update sent to Live emergency bridge.',
      'sos_active_update_sent_channel': 'Update sent to incident channel.',
      'sos_active_could_not_send_update': 'Could not send update.',
      'sos_active_voice_text_sent': 'Voice text update sent to the emergency channel.',
      'sos_active_could_not_send_voice': 'Could not send voice update. Try again.',
      'sos_active_voice_update_sent': 'Voice update sent.',
      'sos_active_voice_record_failed':
          'Voice recording failed to send. Try again.',
      'sos_active_routes_to_you': 'Routes to you',
      'sos_active_avg_response_time': 'Avg Response Time:',
      'sos_active_recent_volume': 'Recent Incident Volume:',
      'sos_active_congestion_warning': 'Congestion Warning:',
      'step_prefix': 'Step',
      'highlights_steps': 'Highlights steps one by one',
      'offline_mode': 'OFFLINE MODE — Network disconnected',
      'volunteer': 'Volunteer',
      'unranked': 'Unranked',
      'live': 'Live',
      'you': 'YOU',
      'saved': 'saved',
      'xp_responses': 'XP · {0} responses',
      'duty_monitoring': 'Incoming SOS pop-ups are ON while you are on duty.',
      'turn_on_duty_msg': 'Turn ON DUTY to receive SOS pop-ups.',
      'on_duty_snack': 'ON DUTY — Monitoring for incidents in your area...',
      'off_duty_snack': 'STANDBY — Duty session recorded.',
      'nearby_volunteers_locating': 'Finding your position…',
      'active_volunteers_grid_none': 'No other volunteers in your grid yet',
      'active_volunteers_grid': '{n} active volunteers in your grid',
      'leaderboard_offline': 'LEADERBOARD OFFLINE',
      'leaderboard_offline_sub': 'Syncing paused. Cached scores shown.',
      'leaderboard_empty_primary': 'No response scores yet',
      'leaderboard_empty_secondary':
          'Ranks list volunteers who have accepted an SOS. Past acceptances from archived incidents count here too.',
      'leaderboard_on_duty_fallback_title': 'Volunteers on duty now',
      'leaderboard_on_duty_stat': 'On duty',
      'leaderboard_view_grid': 'Open emergency grid',
      'leaderboard_solo_on_duty':
          "You're on duty. Open the grid to see coverage; other volunteers appear here when they go on duty.",
      'set_sos_pin_first': 'Set SOS PIN first',
      'set_pin_safety_msg': 'For safety, you must set an SOS PIN before creating SOS incidents.',
      'set_pin_now': 'Set PIN now',
      'later': 'Later',
      'emergency_consent_title': 'Emergency data & privacy',
      'emergency_consent_body':
          'When you trigger SOS, EmergencyOS may share your live location, optional profile '
          'medical notes you added in Profile, and voice/updates with volunteers and services '
          'you connect with through the app. '
          'Practice / drill mode does not send a real dispatch.\n\n'
          'You can review or reduce profile data anytime in Profile before an emergency.',
      'consent_not_now': 'Not now',
      'consent_continue': 'I understand — continue',
      'sos_screen_title': 'SOS TRIGGER',
      'sos_hold_banner': 'Only a 3-second hold can trigger SOS',
      'sos_hold_button': 'HOLD 3 SECONDS TO TRIGGER SOS',
      'sos_offline_queued':
          'OFFLINE — SOS QUEUED. Your emergency will be automatically broadcast to responders when connectivity is restored.',
      'sos_semantics_hold_hint':
          'Hold for 3 seconds to trigger SOS emergency alert. Release early to cancel.',
      'sos_starting': 'Starting SOS...',
      'sos_release_to_send': 'Release to send SOS (enables voice guidance).',
      'sos_release_cancel': 'Release early to cancel.',
      'sos_check_connection_retry': 'Check connection and retry.',
      'sos_failed_prefix': 'SOS failed: {detail}',
      'sos_retry': 'RETRY',
      'sos_active_flow_failed': 'Could not start SOS active flow. Please try again.',
      'sos_pin_dispatch_body':
          'For safety, set your SOS PIN in Profile before dispatching SOS.',
      'volunteer_voice_mode_title': 'Choose your volunteer mode',
      'volunteer_voice_mode_subtitle':
          'Before you enter the mission view, pick how you want guidance during this call.',
      'volunteer_voice_mode_audio_title': 'Audio guidance on',
      'volunteer_voice_mode_audio_subtitle':
          'Spoken prompts and updates while you navigate and triage.',
      'volunteer_voice_mode_silent_title': 'Silent (visual-only)',
      'volunteer_voice_mode_silent_subtitle':
          'No text-to-speech; follow on-screen cards and checklists only.',
      'volunteer_voice_mode_footer':
          'You can change this preference later from the SOS and Lifeline settings.',
      'cancel': 'Cancel',
      'continue': 'Continue',
      'close': 'Close',
      'unlock': 'Unlock',
      'pin': 'PIN',
      'save': 'Save',
      'pin_change_title': 'Change SOS PIN',
      'pin_set_title': 'Set SOS PIN',
      'pin_hint_new': 'New PIN',
      'pin_hint_confirm': 'Confirm PIN',
      'pin_error_too_short': 'PIN must be at least 4 digits.',
      'pin_error_mismatch': 'PINs do not match.',
      'wrong_pin': 'Wrong PIN.',
      'wrong_pin_practice': 'Wrong PIN. Practice PIN is {pin}.',
      'no_sos_pin_set': 'No SOS PIN set. Set it in Profile first.',
      'sign_in_to_unlock': 'Sign in to unlock with Profile PIN.',
      'sos_actions_title': 'SOS Actions',
      'sos_actions_cancel_false_alarm': 'Cancel SOS (false alarm)',
      'sos_actions_mark_resolved_safe': 'Mark Resolved (safe)',
      'sos_actions_unlock_and_leave': 'Just unlock & leave (keep SOS running)',
      'sos_other_emergency_title': 'Other emergency',
      'sos_other_emergency_hint': 'Briefly describe what is happening…',
      'sos_other_emergency_value_other': 'Other',
      'sos_other_emergency_value_other_with_detail': 'Other: {detail}',
      'sos_are_you_conscious': 'Are you conscious? Please answer yes or no.',
      'sos_tts_opening_guidance':
          'Your SOS is active. Help is on the way. Follow the spoken prompts and tap to answer.',
      'sos_interview_q1_prompt': 'What is happening? (type of emergency)',
      'sos_interview_q2_prompt': 'Are you safe? How serious is it?',
      'sos_interview_q3_prompt': 'How many people are involved?',
      'sos_chip_cat_accident': 'Accident',
      'sos_chip_cat_medical': 'Medical',
      'sos_chip_cat_hazard': 'Hazard (fire, drowning, etc.)',
      'sos_chip_cat_assault': 'Assault',
      'sos_chip_cat_other': 'Other',
      'sos_chip_safe_critical': 'Critical (life-threatening)',
      'sos_chip_safe_injured': 'Injured but stable',
      'sos_chip_safe_danger': 'Not injured but in danger',
      'sos_chip_safe_safe_now': 'Safe now',
      'sos_chip_people_me': 'Only me',
      'sos_chip_people_two': 'Two',
      'sos_chip_people_many': 'More than two',
      'sos_tts_interview_saved':
          'All victim interview data has been saved. Responders now have detailed information. Consciousness checks will continue every 60 seconds.',
      'sos_tts_map_routes':
          'Open the map tab: solid red is the driving route to the assigned hospital when dispatch sets one, or a short approach path until then. Green shows the assigned volunteer live GPS marker. Stay on the emergency voice channel so responders can hear you.',
      'sos_tts_emergency_contacts_on_file':
          'Your emergency contact from your profile is attached to this SOS. SMS updates may be sent when that option is enabled.',
      'sos_tts_conscious_no_answer_attempt':
          'No answer. Consciousness check attempt {n} of {max}. We will ask again in one minute.',
      'voice_volunteer_accepted': 'Volunteer accepted. Help is on the way.',
      'voice_ambulance_dispatched_eta':
          'Ambulance dispatched. Estimated arrival: {eta}.',
      'voice_police_dispatched_eta':
          'Police dispatched. Estimated arrival: {eta}.',
      'voice_ambulance_on_scene_victim':
          'Ambulance is on scene — about two hundred metres from you.',
      'voice_ambulance_on_scene_volunteer':
          'Ambulance is on scene — within about two hundred metres of the incident.',
      'voice_ambulance_returning': 'Ambulance is returning to hospital.',
      'voice_response_complete_station':
          'Response complete. Ambulance at station.',
      'voice_response_complete_cycle':
          'Response complete. Ambulance at station. Total response cycle {minutes} minutes {seconds} seconds.',
      'voice_volunteers_on_scene_count':
          '{n} volunteers are on scene now.',
      'voice_one_volunteer_on_scene': 'One volunteer is on scene.',
      'voice_ptt_joined_comms': '{who} joined voice communications.',
      'voice_ptt_responder_default': 'A responder',
      'voice_tts_unavailable_banner':
          'Voice guidance is unavailable — please read the on-screen captions.',
      'language_picker_title': 'Language',
      'ops_tray_uptime': 'Uptime {time}',
      'drill_sos_step_0_title': 'Victim practice shell',
      'drill_sos_step_0_body':
          'You are in a separate practice area (URLs start with /drill). It looks like the real app but uses demo data only — your normal Home at /dashboard is untouched. We will walk through every bottom tab, then you will use the red SOS button.',
      'drill_sos_step_1_title': 'Step 1 — Home (Practice)',
      'drill_sos_step_1_body':
          'Tap Home (cottage icon) below. You should see drill exit controls at the top; the leaderboard and stats use your live account data.',
      'drill_sos_step_2_title': 'Step 2 — Grid map',
      'drill_sos_step_2_body':
          'Tap Grid. On the practice map you will see demo active SOS pins (pulsing) and you can tap the folder (Archived SOS) for demo closed incidents. None of this is a real dispatch.',
      'drill_sos_step_3_title': 'Step 3 — Lifeline',
      'drill_sos_step_3_body':
          'Tap Lifeline and skim the guides — same layout as production. The cyan bar says you are still in practice.',
      'drill_sos_step_4_title': 'Step 4 — Profile',
      'drill_sos_step_4_body':
          'Tap Profile. Same screens as live; the banner reminds you this is still the drill shell.',
      'drill_sos_step_5_title': 'Step 5 — Back to Home',
      'drill_sos_step_5_body':
          'Tap Home again and confirm you see the practice dashboard. When you are there, tap Next.',
      'drill_sos_step_6_title': 'Step 6 — Open practice SOS (3 second hold)',
      'drill_sos_step_6_body':
          'Do not expect this tour to open SOS for you.\n\n1) Put your finger on the red circular SOS button (below the screen, center).\n2) Press and hold — keep holding.\n3) Wait until the white ring fills completely (about 3 seconds), then release.\n\nThat opens SOS practice only. Got it closes this guide so you can perform the hold.',
      'drill_vol_step_0_title': 'Volunteer practice shell',
      'drill_vol_step_0_body':
          'You are in a separate practice area that mirrors live ops (not the real dashboard). After Continue you will get a practice incoming alert, then MAP / TRIAGE / ON-SCENE with demo vehicles and logs only.',
      'drill_vol_step_1_title': 'Home first',
      'drill_vol_step_1_body':
          'Real responders wait here for push/FCM. The next step is the same full-screen swipe alert you get on duty.',
      'drill_vol_step_2_title': 'Routes & ETAs',
      'drill_vol_step_2_body':
          'After you accept, vehicles follow road polylines; the top card shows zone, responder count, and EMS ETA. The triage log fills in over time like a live mission.',
      'drill_vol_step_3_title': 'Practice alert next',
      'drill_vol_step_3_body':
          'Tap Continue, then swipe all the way to accept — same gesture as production. Alarm is muted in drill.',
      'volunteer_victim_medical_card': 'Victim medical card',
      'volunteer_dispatch_milestone_title': 'Dispatch updates',
      'volunteer_dispatch_milestone_hospital': 'Hospital accepted: {hospital}',
      'volunteer_dispatch_milestone_unit': 'Ambulance unit: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'Ambulance crew: coordinating…',
      'volunteer_dispatch_milestone_en_route': 'Ambulance en route',
      'volunteer_triage_qr_report_title': 'QR or tap report',
      'volunteer_triage_qr_report_subtitle':
          'Scan the code for a handoff payload or tap to save a narrative report on this incident.',
      'volunteer_triage_show_qr': 'Show QR',
      'volunteer_triage_tap_report': 'Tap report',
      'volunteer_triage_qr_title': 'Incident handoff QR',
      'volunteer_triage_qr_body': 'Share this code with receiving staff or EMS for a structured payload.',
      'volunteer_triage_report_saved': 'Report saved under this incident.',
      'volunteer_triage_report_failed': 'Could not save report: ',
      'volunteer_victim_medical_offline_hint':
          'From SOS packet — available from device cache when offline.',
      'volunteer_victim_consciousness_title': 'Consciousness',
      'volunteer_victim_three_questions': 'Initial victim answers',
      'volunteer_major_updates_log': 'Major updates only',
      'volunteer_more_triage_details': 'More triage & vitals',
      'volunteer_more_victim_details': 'More victim details',
      'volunteer_sos_intake_title': 'SOS intake (victim app)',
      'volunteer_show_full_qa': 'Show full Q&A',
      'volunteer_full_qa_sheet_title': 'Victim safety Q&A (full)',
      'volunteer_victim_label_conscious': 'Conscious',
      'volunteer_victim_label_breathing': 'Breathing',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'Escalating to tier {tier}. Trying hospital {hospital}.',
      'volunteer_dispatch_trying_hospital': 'Trying hospital {hospital}.',
      'volunteer_dispatch_hospital_accepted':
          '{hospital} has accepted the emergency. Ambulance coordination underway.',
      'volunteer_dispatch_all_hospitals_notified':
          'All hospitals notified. Escalating to emergency services.',
      'sos_dispatch_alerting_nearest_trying':
          'Alerting nearest hospital in your area. Trying {hospital}.',
      'sos_dispatch_escalating_tier_trying':
          'No response. Escalating to tier {tier}. Trying {hospital}.',
      'sos_dispatch_retry_previous_trying':
          'No response from previous hospital. Trying {hospital}.',
      'sos_dispatch_all_hospitals_call_112':
          'All hospitals notified. Please call 112 for emergency services.',
      'profile_synced': 'Synced',
      'profile_not_synced': 'Not synced',
      'profile_saving': 'Saving…',
      'profile_queued_offline': 'Queued (offline)',
      'profile_save_failed': 'Save failed',
      'profile_save_timed_out': 'Save timed out',
      'profile_time_just_now': 'just now',
      'profile_time_min_ago': '{n} min ago',
      'profile_time_hours_ago': '{n}h ago',
      'profile_time_days_ago': '{n}d ago',
      'profile_db_unreachable':
          'Could not reach database. Is Cloud Firestore enabled?',
      'profile_saved_offline_msg': 'Saved locally — will sync when online.',
      'profile_saved_msg': 'Medical info saved successfully.',
      'profile_save_timeout_msg':
          'Save timed out. Please check your internet or Firebase console.',
      'profile_save_error': 'Error saving info: {e}',
      'profile_pin_saved_offline': 'PIN saved locally — will sync when online.',
      'profile_pin_saved': 'SOS PIN saved.',
      'profile_pin_save_error': 'Could not save SOS PIN: {e}',
      'drill_profile_banner':
          'Practice Profile — same layout as live; changes here still save to your account when signed in.',
      'profile_sms_contact_title': 'Send emergency updates to this contact (SMS)',
      'profile_sms_contact_subtitle':
          'When responders accept or ETAs change, EmergencyOS can text your emergency contact.',
      'profile_dispatch_desk_title': 'I am emergency dispatch (join Lifeline WebRTC)',
      'profile_dispatch_desk_subtitle':
          'Enable only for official EMS/dispatch accounts. Lets you join Lifeline as dispatch on active volunteer incidents (not for general volunteers).',
      'profile_pin_status_set': 'PIN is set',
      'profile_pin_status_unset': 'PIN not set',
      'profile_change_pin_btn': 'Change PIN',
      'profile_set_pin_btn': 'Set PIN',
      'profile_pin_exit_note':
          'This PIN is required to exit the SOS Active screen and to cancel/resolve an SOS.',
      'profile_sos_pin_title': 'SOS PIN lock',
      'profile_voice_agent_enable_title': 'Enable Lifeline voice agent',
      'profile_voice_agent_enable_subtitle': 'Shows voice controls on the Lifeline page.',
      'profile_voice_start_muted_title': 'Start with microphone muted',
      'profile_voice_start_muted_subtitle':
          'When connecting, mic stays off until you unmute on the orb.',
      'profile_voice_walkthrough_title': 'Full walkthrough mode',
      'profile_voice_walkthrough_subtitle':
          'Allows Lifeline voice to request SOS (you must still confirm in the app).',
      'profile_unsaved_title': 'Discard changes?',
      'profile_unsaved_body': 'You have unsaved medical profile changes.',
      'profile_stay': 'Keep editing',
      'profile_discard': 'Discard',
      'profile_additional_info': 'Additional medical info',
      'profile_pronouns_title': 'Map avatar pronouns',
      'profile_pronouns_he_him': 'He / him',
      'profile_pronouns_she_her': 'She / her',
      'profile_pronouns_they_them': 'They / them',
      'profile_tab_volunteer_hub': 'Volunteer hub',
      'profile_volunteer_certifications_title': 'Certifications',
      'profile_volunteer_certifications_subtitle':
          'Upload CPR and AED certificates for verification.',
      'profile_cpr_certified_title': 'CPR certified',
      'profile_cpr_certified_subtitle': 'Mark when your CPR training is current.',
      'profile_aed_certified_title': 'AED certified',
      'profile_aed_certified_subtitle': 'Mark when your AED training is current.',
      'profile_cert_uploading': 'Uploading…',
      'profile_upload_cpr_cert': 'Upload CPR certificate',
      'profile_upload_aed_cert': 'Upload AED certificate',
      'profile_cert_upload_no_bytes': 'Could not read the selected file.',
      'profile_cert_uploaded': 'Certificate uploaded.',
      'profile_cert_upload_failed': 'Upload failed: {e}',
      'help_screen_title': 'Help & support',
      'profile_stat_never': 'Never',
      'profile_loading': 'Loading…',
      'profile_error': 'Could not load',
      'profile_volunteer_stats_title': 'Your impact',
      'profile_stat_incidents_responded': 'Incidents responded',
      'profile_stat_total_lives_saved': 'Lives helped (estimate)',
      'profile_stat_last_incident': 'Last response',
      'profile_stat_value_created': 'Member since',
      'profile_stat_value_created_hint': 'Based on your account activity.',
      'profile_hint_blood_type': 'e.g. O+',
      'profile_hint_allergies': 'e.g. Penicillin, Peanuts',
      'profile_hint_conditions': 'e.g. Asthma, Diabetes',
      'profile_hint_contact_name': 'John Doe',
      'profile_hint_relationship': 'e.g. Spouse, Parent',
      'profile_hint_phone': '+1 234 567 8900',
      'profile_hint_contact_email': 'name@example.com',
      'profile_hint_medications': 'e.g. Insulin, Blood Thinners',
      'profile_hint_donor': 'Yes / No',
      'home_duty_heading': "Today's Duty",
      'home_duty_progress': '{done} of {total} prep steps done',
      'home_map_semantics': 'Map showing your area and emergency grid',
      'home_recenter_map': 'Recenter map on my location',
      'home_sos_large_fab_hint': 'Open SOS countdown to send an emergency alert',
      'home_sos_cancelled_snack': 'SOS cancelled.',
      'home_sos_sent_snack': 'SOS sent! Emergency services notified.',
      'quick_sos_title': 'QUICK SOS',
      'quick_sos_subtitle': 'Tap to answer — help arrives faster with details',
      'quick_sos_practice_banner':
          'Practice guided intake — Submit will not create a real SOS. Use Home + 3s hold on the red SOS for the drill scenario.',
      'quick_sos_section_what': "WHAT'S THE EMERGENCY?",
      'quick_sos_section_someone_else': 'ARE YOU TRIGGERING SOS FOR SOMEONE ELSE?',
      'quick_sos_send_now': 'SEND SOS NOW',
      'quick_sos_select_first': 'Select emergency type and confirm',
      'quick_sos_section_victim': 'VICTIM STATUS',
      'quick_sos_victim_subtitle': 'Helps responders prepare the right equipment',
      'quick_sos_section_people': 'HOW MANY PEOPLE NEED HELP?',
      'quick_sos_yes_someone_else': 'YES — for someone else',
      'quick_sos_no_for_me': "NO — it's for me",
      'quick_sos_other_hint': 'Briefly describe your situation...',
      'quick_sos_close': 'Close quick SOS',
      'quick_sos_drill_submit_disabled':
          'Practice shell: intake submit is disabled. Go to Home and press & hold the red SOS button for 3 seconds to open the drill SOS screen.',
      'quick_sos_failed': 'SOS failed: {detail}',
      'quick_sos_could_not_start': 'Could not start SOS. Please try again.',
      'quick_sos_victim_conscious_q': 'Is the person conscious?',
      'quick_sos_victim_breathing_q': 'Is the person breathing?',
      'quick_sos_label_yes': 'Yes',
      'quick_sos_label_no': 'No',
      'quick_sos_label_unsure': 'Unsure',
      'quick_sos_person': 'person',
      'quick_sos_people': 'people',
      'quick_sos_people_three_plus': '3+',
      'login_tagline': "Let's save some lives",
      'login_subtitle':
          'Sign in to report emergencies, coordinate with volunteers, and save lives during the Golden Hour.',
      'login_continue_google': 'Continue with Google',
      'login_continue_phone': 'Continue with Phone',
      'login_send_code': 'Send Verification Code',
      'login_verify_login': 'Verify & Login',
      'login_phone_label': 'Phone Number',
      'login_phone_hint': '+1234567890',
      'login_otp_label': 'Verification Code (OTP)',
      'login_back_options': 'Back to options',
      'login_change_phone': 'Change phone number',
      'login_drill_mode': 'Drill mode',
      'login_drill_subtitle': 'Tap to practise — no real SOS',
      'login_drill_semantics': 'Drill mode, practice without a real emergency',
      'login_practise_victim': 'Practise as victim',
      'login_practise_volunteer': 'Practise as volunteer',
      'login_admin_note':
          'Master admin and operator consoles: no separate admin account — tap below. If you are not signed in yet, we use a lightweight anonymous session only for that console.',
      'login_ems_dashboard': 'EMS Dashboard',
      'login_emergency_operator': 'Emergency service operator login',
      'ai_assist_practice_banner':
          'Practice Lifeline — same guides as live mode; nothing is sent to real dispatch.',
      'ai_assist_rail_semantics': 'Lifeline training level {n}: {title}',
      'ai_assist_emergency_toggle_on': 'Emergency mode on, urgent guidance',
      'ai_assist_emergency_toggle_off': 'Emergency mode off',
      'dashboard_exit_drill_title': 'Exit drill mode?',
      'dashboard_exit_drill_body':
          'You will be signed out of this practice session and returned to the login page.',
      'dashboard_back_login_tooltip': 'Back to login',
      'dashboard_exit_drill_confirm': 'Exit',
      'sos_active_title_big': 'ACTIVE SOS',
      'sos_active_help_coming': 'Help is coming. Stay calm.',
      'sos_active_badge_waiting': 'WAITING',
      'sos_active_badge_en_route_count': '{n} EN ROUTE',
      'sos_active_mini_ambulance': 'Ambulance',
      'sos_active_mini_on_scene': 'On scene',
      'sos_active_mini_status': 'Status',
      'sos_active_volunteers_count_short': '{n} volunteers',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title': 'All hospitals notified',
      'sos_active_all_hospitals_notified_subtitle':
          'No hospital accepted in time. Dispatch is escalating to emergency services.',
      'sos_active_position_refresh_note':
          'Your position is refreshed about every 45 seconds during SOS to save battery. Keep the app open and plug in if you can.',
      'sos_active_mic_active': 'Mic · Active',
      'sos_active_mic_active_detail':
          'Live channel is receiving your microphone.',
      'sos_active_mic_standby': 'Mic · Standby',
      'sos_active_mic_standby_detail': 'Waiting for voice channel…',
      'sos_active_mic_connecting': 'Mic · Connecting',
      'sos_active_mic_connecting_detail': 'Joining emergency voice channel…',
      'sos_active_mic_reconnecting': 'Mic · Reconnecting',
      'sos_active_mic_reconnecting_detail': 'Restoring live audio…',
      'sos_active_mic_failed': 'Mic · Disrupted',
      'sos_active_mic_failed_detail':
          'Voice channel unavailable. Use RETRY above.',
      'sos_active_mic_ptt_only': 'Mic · Incident channel',
      'sos_active_mic_ptt_only_detail':
          'Operations console routed voice via Firebase PTT. Hold Broadcast to reach responders.',
      'sos_active_mic_interrupted': 'Mic · Interrupted',
      'sos_active_mic_interrupted_detail':
          'Brief pause while the app processes audio.',
      'sos_active_consciousness_note':
          'Answer consciousness checks with YES or NO; other prompts use on-screen options.',
      'sos_active_live_updates_header': 'LIVE UPDATES',
      'sos_active_live_updates_subtitle': 'Dispatch, volunteers & device',
      'sos_active_live_tag': 'Live',
      'sos_active_activity_log': 'Activity log',
      'sos_active_header_stat_coordinating_crew': 'Coordinating crew',
      'sos_active_header_stat_coordinating': 'Coordinating',
      'sos_active_header_stat_en_route': 'En route',
      'sos_active_header_stat_route_min': '~{n} min',
      'sos_active_live_sos_is_live_title': 'SOS is live',
      'sos_active_live_sos_is_live_detail':
          'Your location and medical flags are on the emergency network.',
      'sos_active_live_volunteers_notified_title': 'Volunteers notified',
      'sos_active_live_volunteers_notified_detail':
          'Nearby volunteers receive this incident in real time.',
      'sos_active_live_bridge_connected_title':
          'Emergency voice bridge connected',
      'sos_active_live_bridge_connected_detail':
          'Dispatch desk and responders can hear this channel.',
      'sos_active_live_ptt_title': 'Voice via Firebase PTT',
      'sos_active_live_ptt_detail':
          'Live WebRTC bridge is off for this fleet. Use Broadcast for voice and text updates.',
      'sos_active_live_contacts_notified_title':
          'Emergency contacts notified',
      'sos_active_live_hospital_accepted_title': 'Hospital accepted',
      'sos_active_live_ambulance_unit_assigned_title':
          'Ambulance unit assigned',
      'sos_active_live_ambulance_unit_assigned_subtitle': 'Unit {unit}',
      'sos_active_live_ambulance_en_route_title': 'Ambulance en route',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'En route',
      'sos_active_live_ambulance_en_route_route_eta': '~{n} min (route)',
      'sos_active_live_ambulance_coordination_title': 'Ambulance coordination',
      'sos_active_live_ambulance_coordination_pending':
          'Hospital accepted — alerting ambulance operators.',
      'sos_active_live_ambulance_coordination_arranging':
          'Arranging ambulance crew — minute ETA when unit is en route.',
      'sos_active_live_responder_status_title': 'Responder status',
      'sos_active_live_volunteer_accepted_single_title': 'Volunteer accepted',
      'sos_active_live_volunteer_accepted_many_title': 'Volunteers accepted',
      'sos_active_live_volunteer_accepted_single_detail':
          'A responder is assigned and moving to help you.',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} responders are assigned to this SOS.',
      'sos_active_live_volunteer_on_scene_single_title':
          'Volunteer arrived on scene',
      'sos_active_live_volunteer_on_scene_many_title': 'Volunteers on scene',
      'sos_active_live_volunteer_on_scene_single_detail':
          'Someone is with you or at your pin.',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} responders marked on scene.',
      'sos_active_live_responder_location_title': 'Live responder location',
      'sos_active_live_responder_location_detail':
          'Assigned volunteer GPS is updating on the map.',
      'sos_active_live_professional_dispatch_title':
          'Professional dispatch active',
      'sos_active_live_professional_dispatch_detail':
          'Coordinated services are working this incident.',
      'sos_active_ambulance_200m_detail':
          'Ambulance on scene — within about 200 metres.',
      'sos_active_ambulance_200m_semantic_label':
          'Ambulance on scene within about two hundred metres',
      'sos_active_bridge_channel_on_suffix': ' · {n} on channel',
      'sos_active_bridge_channel_voice': 'Emergency voice channel',
      'sos_active_bridge_channel_ptt': 'Emergency channel · Firebase PTT',
      'sos_active_bridge_channel_failed': 'Emergency channel · tap retry',
      'sos_active_bridge_channel_connecting':
          'Emergency channel · connecting',
      'sos_active_dispatch_contact_hospitals_default':
          'We are contacting nearby hospitals based on your location and emergency type.',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'Ambulance crew notified',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'A partner hospital accepted your case. Ambulance operators are being alerted.',
      'sos_active_dispatch_ambulance_confirmed_title': 'Ambulance confirmed',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'Unit {unit} is en route to you. Stay where responders can reach you.',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'An ambulance is en route to you. Stay where responders can reach you.',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'Ambulance handoff delayed',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'A hospital accepted, but no ambulance crew confirmed in time. Dispatch is escalating — if needed, call 112.',
      'sos_active_dispatch_pending_title_trying': 'Trying: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · Waiting for hospital response.',
      'sos_active_dispatch_accepted_title': '{hospital} accepted',
      'sos_active_dispatch_accepted_subtitle':
          'Ambulance dispatch is being coordinated.',
      'sos_active_dispatch_exhausted_title': 'All hospitals notified',
      'sos_active_dispatch_exhausted_subtitle':
          'No hospital accepted in time. Dispatch is escalating to emergency services.',
      'sos_active_dispatch_generic_title': 'Hospital dispatch',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'Emergency Voice Channel',
      'volunteer_bridge_join_hint_incident':
          'Join uses this incident: emergency contact if your number matches; otherwise accepted volunteer.',
      'volunteer_bridge_join_hint_elite':
          'Join uses your elite volunteer access when you are an accepted responder; otherwise contact if your number matches.',
      'volunteer_bridge_join_hint_desk':
          'You join as dispatch (emergency services desk on your profile).',
      'volunteer_bridge_join_voice_btn': 'Join Voice',
      'volunteer_bridge_connecting_btn': 'Connecting…',
      'volunteer_bridge_incident_id_hint': 'Incident ID',
      'volunteer_consignment_live_location_hint':
          'Your live location is shared with this incident while you are on consignment so the map and ETAs stay accurate.',
      'volunteer_consignment_low_power_label': 'Low power',
      'volunteer_consignment_normal_gps_label': 'Normal GPS',
      'bridge_card_incident_id_missing': 'Incident ID is missing.',
      'bridge_card_ptt_only_snackbar':
          'Operations console routed victim voice via Firebase PTT. WebRTC bridge join is disabled.',
      'bridge_card_ptt_only_banner':
          'Console routed voice via Firebase PTT — LiveKit bridge join is disabled for this fleet.',
      'bridge_card_connected_snackbar': 'Connected to voice channel.',
      'bridge_card_could_not_join': 'Could not join: {err}',
      'bridge_card_voice_channel_title': 'Voice channel',
      'bridge_card_calm_disclaimer':
          'Maintain calm and speak clearly. A steady tone helps the victim and other responders. Avoid shouting or rushing your words.',
      'bridge_card_cancel': 'Cancel',
      'bridge_card_join_voice': 'Join voice',
      'bridge_card_voice_connected': 'Voice Connected',
      'bridge_card_in_channel': '{n} in channel',
      'bridge_card_transmitting': 'Transmitting…',
      'bridge_card_hold_to_talk': 'Hold to talk',
      'bridge_card_disconnect': 'Disconnect',
      'vol_ems_banner_en_route': 'Ambulance en route to scene',
      'vol_ems_banner_on_scene': 'Ambulance on scene (~200 m of incident)',
      'vol_ems_banner_returning': 'Ambulance returning to hospital',
      'vol_ems_banner_complete': 'Response complete · Ambulance at station',
      'vol_ems_banner_complete_with_cycle':
          'Response complete · Ambulance at station · Total cycle {m}m {s}s',
      'vol_tooltip_lifeline_first_aid':
          'Lifeline — first-aid guides (stays on response)',
      'vol_tooltip_exit_mission': 'Exit Mission',
      'vol_low_power_tracking_hint':
          'Low-power tracking: we sync your position less often and only after larger moves. Dispatch still sees your last point.',
      'vol_marker_you': 'You',
      'vol_marker_active_unit': 'Active Unit',
      'vol_marker_practice_incident': 'Practice incident',
      'vol_marker_accident_scene': 'Accident Scene',
      'vol_marker_training_pin': 'Training pin — not a real SOS',
      'vol_marker_high_severity': 'GITM COLLEGE - High Severity',
      'vol_marker_accepted_hospital': 'Accepted: {hospital}',
      'vol_marker_trying_hospital': 'Trying: {hospital}',
      'vol_marker_ambulance_on_scene': 'AMBULANCE ON SCENE!',
      'vol_marker_ambulance_en_route': 'Ambulance En Route',
      'vol_badge_at_scene_pin': 'AT SCENE PIN',
      'vol_badge_in_5km_zone': 'IN 5 KM ZONE',
      'vol_badge_en_route': 'EN ROUTE',
    },

    // ── Hindi (हिन्दी) ─────────────────────────────────────────────────────
    'hi': {
      'app_name': 'EmergencyOS',
      'profile_title': 'प्रोफ़ाइल और मेडिकल आईडी',
      'language': 'भाषा',
      'save_medical_profile': 'मेडिकल प्रोफ़ाइल सहेजें',
      'critical_medical_info': 'महत्वपूर्ण चिकित्सा जानकारी',
      'emergency_contacts': 'आपातकालीन संपर्क',
      'golden_hour_details': 'गोल्डन ऑवर विवरण',
      'sos_lock': 'SOS लॉक',
      'top_life_savers': 'शीर्ष जीवन रक्षक',
      'lives_saved': 'बचाई गई जानें',
      'active_alerts': 'सक्रिय अलर्ट',
      'rank': 'रैंक',
      'on_duty': 'ड्यूटी पर',
      'standby': 'स्टैंडबाय',
      'sos': 'SOS',
      'call_now': 'अभी कॉल करें',
      'quick_guide': 'त्वरित गाइड',
      'detailed_instructions': 'विस्तृत निर्देश',
      'red_flags': 'खतरे के संकेत',
      'cautions': 'सावधानियाँ',
      'voice_walkthrough': 'वॉइस वॉकथ्रू',
      'playing': 'चल रहा है...',
      'swipe_next_guide': 'अगली गाइड के लिए स्वाइप करें',
      'watch_video_guide': 'पूरा वीडियो गाइड देखें',
      'emergency_grid_scan': 'आपातकालीन ग्रिड स्कैन',
      'area_telemetry': 'क्षेत्र टेलीमेट्री और जोखिम सूचकांक',
      'report_hazard': 'खतरा रिपोर्ट करें',
      'todays_duty': 'आज की ड्यूटी',
      'blood_type': 'रक्त प्रकार',
      'allergies': 'एलर्जी',
      'medical_conditions': 'चिकित्सा स्थितियाँ',
      'contact_name': 'प्राथमिक संपर्क नाम',
      'contact_phone': 'प्राथमिक संपर्क फ़ोन',
      'relationship': 'संबंध',
      'medications': 'वर्तमान दवाइयाँ',
      'organ_donor': 'अंग दाता स्थिति',
      'good_morning': 'सुप्रभात,',
      'good_afternoon': 'नमस्कार,',
      'good_evening': 'शुभ संध्या,',
      'hospitals': 'अस्पताल / ट्रॉमा',
      'visual_walkthrough': 'विज़ुअल वॉकथ्रू',
      'lifeline': 'लाइफलाइन',
      'nav_home': 'होम',
      'nav_map': 'मानचित्र',
      'nav_grid': 'ग्रिड',
      'nav_profile': 'प्रोफ़ाइल',
      'map_caching_offline_pct': 'ऑफ़लाइन के लिए क्षेत्र कैश हो रहा है — {pct}%',
      'map_drill_practice_banner':
          'अभ्यास ग्रिड: पल्सिंग पिन = डेमो सक्रिय अलर्ट। लेयर्स के लिए मानचित्र फ़िल्टर — वास्तविक डेटा नहीं।',
      'map_recenter_tooltip': 'फिर केंद्रित करें',
      'map_legend_hospital': 'अस्पताल',
      'map_legend_live_sos_history': 'लाइव SOS / इतिहास',
      'map_legend_past_this_hex': 'पिछला (यह हेक्स)',
      'map_legend_in_area': '{n} क्षेत्र में',
      'map_legend_in_cell': '{n} सेल में',
      'map_legend_volunteers_on_duty': 'ड्यूटी पर स्वयंसेवक',
      'map_legend_volunteers_in_grid': 'ग्रिड में {n}',
      'map_legend_responder_scene': 'प्रतिक्रिया → दृश्य',
      'map_responder_routes_one': '{n} मार्ग',
      'map_responder_routes_many': '{n} मार्ग',
      'map_filters_title': 'मानचित्र फ़िल्टर',
      'volunteer_active_browser_location_off':
          'ब्राउज़र लोकेशन बंद या ब्लॉक है। आप फिर भी घटना मानचित्र देख सकते हैं — अपनी स्थिति दिखाने के लिए साइट सेटिंग में लोकेशन चालू करें।',
      'volunteer_active_location_required': 'इस कंसाइनमेंट के लिए स्थान अनुमति आवश्यक है।',
      'volunteer_active_map_load_failed': 'कंसाइनमेंट मानचित्र लोड नहीं हो सका। {detail}',
      'volunteer_active_no_map_coords': 'इस घटना के मानचित्र निर्देशांक नहीं हैं। कंसाइनमेंट नहीं खोल सकते।',
      'volunteer_active_gps_unavailable':
          'अभी GPS नहीं पढ़ सके। बाहर खोलें या सटीक स्थान चालू करें।',
      'volunteer_active_offline_qr_title': 'ऑफ़लाइन स्थान QR',
      'volunteer_active_offline_qr_body': 'ऑफ़लाइन घटना स्थान पहुँच साझा करने के लिए स्कैन करें।',
      'volunteer_active_close': 'बंद करें',
      'volunteer_active_dispatched_services': 'भेजी गई सेवाएँ',
      'volunteer_active_ambulance': 'एम्बुलेंस',
      'volunteer_active_on_scene': 'मौके पर',
      'volunteer_active_en_route': 'रास्ते में',
      'volunteer_active_exit_title': 'प्रतिक्रिया विंडो बंद करें?',
      'volunteer_active_leave_victim': 'इस घटना दृश्य से बाहर निकलें?',
      'volunteer_active_leave_volunteer':
          'आप इस घटना पर प्रतिक्रिया बंद कर देंगे। असाइनमेंट साफ़ हो जाएगा ताकि ऐप आपको यहाँ वापस न भेजे।',
      'volunteer_active_stay': 'रुकें',
      'volunteer_active_exit': 'बाहर निकलें',
      'volunteer_active_sos_expired': 'यह SOS समाप्त (1 घंटा) हो चुका है और संग्रहीत किया गया।',
      'volunteer_active_back_to_response': 'प्रतिक्रिया पर वापस',
      'volunteer_active_offline_qr_access': 'ऑफ़लाइन QR पहुँच',
      'volunteer_active_hospital_ev_label': 'अस्पताल और आपात वाहन',
      'volunteer_active_hospital_ev_subtitle':
          'जैसे-जैसे आप पास आते हैं, मार्ग अनुमान इस घटना में लिखे जाते हैं। पिन के पास वास्तविक सुविधाओं के लिए मानचित्र खोलें।',
      'volunteer_active_nearby_hospitals_maps': 'Google मानचित्र में पास के अस्पताल',
      'volunteer_active_checklist_saved': 'दृश्य चेकलिस्ट डिस्पैच और अन्य प्रतिक्रियाकर्ताओं के लिए सहेजी गई।',
      'volunteer_active_save_failed': 'सहेज नहीं सके: {detail}',
      'volunteer_active_photo_limit': 'अधिकतम 3 दृश्य फ़ोटो अपलोड कर सकते हैं।',
      'volunteer_active_photo_error': 'फ़ोटो त्रुटि: {detail}',
      'volunteer_active_victim_loading': 'पीड़ित जानकारी लोड हो रही है…',
      'sos_active_update_sent_livekit': 'लाइव आपातकालीन ब्रिज पर अपडेट भेजा गया।',
      'sos_active_update_sent_channel': 'घटना चैनल पर अपडेट भेजा गया।',
      'sos_active_could_not_send_update': 'अपडेट नहीं भेज सके।',
      'sos_active_voice_text_sent': 'आवाज़ टेक्स्ट अपडेट आपात चैनल पर भेजा गया।',
      'sos_active_could_not_send_voice': 'आवाज़ अपडेट नहीं भेज सके। फिर कोशिश करें।',
      'sos_active_voice_update_sent': 'आवाज़ अपडेट भेजा गया।',
      'sos_active_voice_record_failed': 'आवाज़ रिकॉर्डिंग भेजी नहीं जा सकी। फिर कोशिश करें।',
      'sos_active_routes_to_you': 'आपकी ओर मार्ग',
      'sos_active_avg_response_time': 'औसत प्रतिक्रिया समय:',
      'sos_active_recent_volume': 'हाल की घटना मात्रा:',
      'sos_active_congestion_warning': 'भीड़ चेतावनी:',
      'step_prefix': 'चरण',
      'highlights_steps': 'एक-एक करके चरण दिखाता है',
      'offline_mode': 'ऑफ़लाइन मोड — नेटवर्क डिस्कनेक्ट',
      'volunteer': 'स्वयंसेवक',
      'unranked': 'अनरैंक्ड',
      'live': 'लाइव',
      'you': 'आप',
      'saved': 'बचाए',
      'xp_responses': 'XP · {0} प्रतिक्रियाएँ',
      'duty_monitoring': 'जब आप ड्यूटी पर हैं तो SOS पॉप-अप चालू हैं।',
      'turn_on_duty_msg': 'SOS पॉप-अप प्राप्त करने के लिए ड्यूटी चालू करें।',
      'on_duty_snack': 'ड्यूटी पर — आपके क्षेत्र में घटनाओं की निगरानी...',
      'off_duty_snack': 'स्टैंडबाय — ड्यूटी सत्र दर्ज किया गया।',
      'nearby_volunteers_locating': 'आपकी स्थिति ढूँढ रहे हैं…',
      'active_volunteers_grid_none': 'आपके ग्रिड में अभी कोई अन्य स्वयंसेवक नहीं',
      'active_volunteers_grid': 'आपके ग्रिड में {n} सक्रिय स्वयंसेवक',
      'leaderboard_offline': 'लीडरबोर्ड ऑफ़लाइन',
      'leaderboard_offline_sub': 'सिंकिंग रुकी। कैश्ड स्कोर दिखाए गए।',
      'leaderboard_empty_primary': 'अभी कोई प्रतिक्रिया स्कोर नहीं',
      'leaderboard_empty_secondary':
          'रैंक उन स्वयंसेवकों की है जिन्होंने SOS स्वीकार किया है। संग्रहीत घटनाओं से पुराने स्वीकृति भी गिने जाते हैं।',
      'leaderboard_on_duty_fallback_title': 'अभी ड्यूटी पर स्वयंसेवक',
      'leaderboard_on_duty_stat': 'ड्यूटी पर',
      'leaderboard_view_grid': 'आपातकालीन ग्रिड खोलें',
      'leaderboard_solo_on_duty':
          'आप ड्यूटी पर हैं। कवरेज देखने के लिए ग्रिड खोलें; अन्य स्वयंसेवक ड्यूटी पर आने पर यहाँ दिखेंगे।',
      'set_sos_pin_first': 'पहले SOS पिन सेट करें',
      'set_pin_safety_msg': 'सुरक्षा के लिए, SOS बनाने से पहले पिन सेट करना आवश्यक है।',
      'set_pin_now': 'अभी पिन सेट करें',
      'later': 'बाद में',
      'emergency_consent_title': 'आपातकालीन डेटा और गोपनीयता',
      'emergency_consent_body':
          'जब आप SOS ट्रिगर करते हैं, EmergencyOS आपका लाइव स्थान, प्रोफ़ाइल में जोड़ा वैकल्पिक चिकित्सा विवरण, '
          'और आवाज़/अपडेट उन स्वयंसेवकों और सेवाओं के साथ साझा कर सकता है जिनसे आप ऐप के ज़रिए जुड़ते हैं। '
          'अभ्यास / ड्रिल मोड वास्तविक डिस्पैच नहीं भेजता।\n\n'
          'आपातकाल से पहले कभी भी प्रोफ़ाइल में डेटा देख या कम कर सकते हैं।',
      'consent_not_now': 'अभी नहीं',
      'consent_continue': 'समझ गया — जारी रखें',
      'sos_screen_title': 'SOS ट्रिगर',
      'sos_hold_banner': 'केवल 3 सेकंड दबाए रखने पर SOS चालू होगा',
      'sos_hold_button': 'SOS के लिए 3 सेकंड दबाए रखें',
      'sos_offline_queued':
          'ऑफ़लाइन — SOS कतार में। कनेक्टिविटी लौटने पर आपकी आपातकालीन सूचना स्वतः प्रतिक्रियाकर्ताओं तक पहुँचेगी।',
      'sos_semantics_hold_hint':
          'SOS के लिए 3 सेकंड दबाए रखें। रद्द करने के लिए जल्दी छोड़ें।',
      'sos_starting': 'SOS शुरू हो रहा है...',
      'sos_release_to_send': 'भेजने के लिए छोड़ें (वॉइस गाइड के लिए)।',
      'sos_release_cancel': 'रद्द करने के लिए जल्दी छोड़ें।',
      'sos_check_connection_retry': 'कनेक्शन जाँचें और फिर कोशिश करें।',
      'sos_failed_prefix': 'SOS विफल: {detail}',
      'sos_retry': 'फिर कोशिश',
      'sos_active_flow_failed': 'SOS सक्रिय स्क्रीन शुरू नहीं हो सकी। पुनः प्रयास करें।',
      'sos_pin_dispatch_body':
          'सुरक्षा के लिए, SOS भेजने से पहले प्रोफ़ाइल में अपना SOS पिन सेट करें।',
      'volunteer_voice_mode_title': 'स्वयंसेवक मोड चुनें',
      'volunteer_voice_mode_subtitle':
          'मिशन दृश्य खोलने से पहले चुनें कि इस कॉल के दौरान मार्गदर्शन कैसे चाहिए।',
      'volunteer_voice_mode_audio_title': 'ऑडियो गाइडेंस चालू',
      'volunteer_voice_mode_audio_subtitle':
          'रूट और ट्रायाज के दौरान बोले गए प्रॉम्प्ट और अपडेट।',
      'volunteer_voice_mode_silent_title': 'साइलेंट (केवल विज़ुअल)',
      'volunteer_voice_mode_silent_subtitle':
          'कोई टेक्स्ट-टू-स्पीच नहीं; केवल ऑन-स्क्रीन कार्ड और चेकलिस्ट देखें।',
      'volunteer_voice_mode_footer':
          'आप बाद में SOS और Lifeline सेटिंग्स में यह पसंद बदल सकते हैं।',
      'cancel': 'रद्द',
      'continue': 'जारी रखें',
      'close': 'बंद करें',
      'unlock': 'अनलॉक',
      'pin': 'पिन',
      'save': 'सहेजें',
      'pin_change_title': 'SOS पिन बदलें',
      'pin_set_title': 'SOS पिन सेट करें',
      'pin_hint_new': 'नया पिन',
      'pin_hint_confirm': 'पिन की पुष्टि',
      'pin_error_too_short': 'पिन कम से कम 4 अंक का हो।',
      'pin_error_mismatch': 'पिन मेल नहीं खाते।',
      'wrong_pin': 'गलत पिन।',
      'wrong_pin_practice': 'गलत पिन। अभ्यास पिन {pin} है।',
      'no_sos_pin_set': 'SOS पिन सेट नहीं है। पहले प्रोफ़ाइल में सेट करें।',
      'sign_in_to_unlock': 'प्रोफ़ाइल पिन से अनलॉक करने के लिए साइन इन करें।',
      'sos_actions_title': 'SOS क्रियाएँ',
      'sos_actions_cancel_false_alarm': 'SOS रद्द करें (गलत अलार्म)',
      'sos_actions_mark_resolved_safe': 'समाधान चिह्नित करें (सुरक्षित)',
      'sos_actions_unlock_and_leave': 'सिर्फ अनलॉक करें और बाहर जाएँ (SOS जारी रहे)',
      'sos_other_emergency_title': 'अन्य आपात स्थिति',
      'sos_other_emergency_hint': 'संक्षेप में बताएं क्या हो रहा है…',
      'sos_other_emergency_value_other': 'अन्य',
      'sos_other_emergency_value_other_with_detail': 'अन्य: {detail}',
      'sos_are_you_conscious': 'क्या आप होश में हैं? कृपया हाँ या ना में जवाब दें।',
      'sos_tts_opening_guidance':
          'आपका SOS सक्रिय है। मदद रास्ते में है। बोले गए संकेतों का पालन करें और जवाब देने के लिए टैप करें।',
      'sos_interview_q1_prompt': 'क्या हो रहा है? (आपातकाल का प्रकार)',
      'sos_interview_q2_prompt': 'क्या आप सुरक्षित हैं? यह कितना गंभीर है?',
      'sos_interview_q3_prompt': 'कितने लोग शामिल हैं?',
      'sos_chip_cat_accident': 'दुर्घटना',
      'sos_chip_cat_medical': 'चिकित्सा',
      'sos_chip_cat_hazard': 'खतरा (आग, डूबना, आदि)',
      'sos_chip_cat_assault': 'हमला',
      'sos_chip_cat_other': 'अन्य',
      'sos_chip_safe_critical': 'गंभीर (जानलेवा)',
      'sos_chip_safe_injured': 'घायल लेकिन स्थिर',
      'sos_chip_safe_danger': 'घायल नहीं लेकिन खतरे में',
      'sos_chip_safe_safe_now': 'अब सुरक्षित',
      'sos_chip_people_me': 'केवल मैं',
      'sos_chip_people_two': 'दो',
      'sos_chip_people_many': 'दो से अधिक',
      'sos_tts_interview_saved':
          'सभी पीड़ित साक्षात्कार डेटा सहेज लिया गया। बचावकर्ताओं के पास विस्तृत जानकारी है। हर 60 सेकंड में चेतना जांच जारी रहेगी।',
      'sos_tts_map_routes':
          'मानचित्र टैब खोलें: ठोस लाल असाइन किए गए अस्पताल की सड़क मार्ग है जब डिस्पैच सेट करता है, अन्यथा तब तक एक छोटा पहुँच मार्ग। हरा असाइन किए गए स्वयंसेवक की मार्ग है। आपातकालीन आवाज़ चैनल पर बने रहें ताकि बचावकर्ता आपको सुन सकें।',
      'sos_tts_emergency_contacts_on_file':
          'आपकी प्रोफ़ाइल का आपातकालीन संपर्क इस SOS से जुड़ा है। विकल्प चालू होने पर SMS अपडेट भेजे जा सकते हैं।',
      'sos_tts_conscious_no_answer_attempt':
          'कोई जवाब नहीं। चेतना जांच प्रयास {n} में से {max}। हम एक मिनट में फिर पूछेंगे।',
      'voice_volunteer_accepted':
          'स्वयंसेवक ने स्वीकार किया। मदद रास्ते में है।',
      'voice_ambulance_dispatched_eta':
          'एम्बुलेंस रवाना। अनुमानित आगमन: {eta}।',
      'voice_police_dispatched_eta':
          'पुलिस रवाना। अनुमानित आगमन: {eta}।',
      'voice_ambulance_on_scene_victim':
          'एम्बुलेंस मौके पर है — आपसे लगभग दो सौ मीटर की दूरी पर।',
      'voice_ambulance_on_scene_volunteer':
          'एम्बुलेंस मौके पर है — घटनास्थल से लगभग दो सौ मीटर के भीतर।',
      'voice_ambulance_returning': 'एम्बुलेंस अस्पताल लौट रही है।',
      'voice_response_complete_station':
          'प्रतिक्रिया पूर्ण। एम्बुलेंस स्टेशन पर।',
      'voice_response_complete_cycle':
          'प्रतिक्रिया पूर्ण। एम्बुलेंस स्टेशन पर। कुल चक्र {minutes} मिनट {seconds} सेकंड।',
      'voice_volunteers_on_scene_count':
          '{n} स्वयंसेवक अब मौके पर हैं।',
      'voice_one_volunteer_on_scene': 'एक स्वयंसेवक मौके पर है।',
      'voice_ptt_joined_comms': '{who} ने आवाज़ संचार में शामिल हुए।',
      'voice_ptt_responder_default': 'एक उत्तरदाता',
      'voice_tts_unavailable_banner':
          'आवाज़ मार्गदर्शन उपलब्ध नहीं — कृपया स्क्रीन पर दिए गए टेक्स्ट पढ़ें।',
      'language_picker_title': 'भाषा',
      'volunteer_victim_medical_card': 'पीड़ित चिकित्सा कार्ड',
      'volunteer_dispatch_milestone_title': 'डिस्पैच अपडेट',
      'volunteer_dispatch_milestone_hospital': 'अस्पताल स्वीकृत: {hospital}',
      'volunteer_dispatch_milestone_unit': 'एम्बुलेंस यूनिट: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'एम्बुलेंस क्रू: समन्वय…',
      'volunteer_dispatch_milestone_en_route': 'एम्बुलेंस रास्ते में',
      'volunteer_triage_qr_report_title': 'QR या टैप रिपोर्ट',
      'volunteer_triage_qr_report_subtitle':
          'हैंडऑफ़ के लिए कोड स्कैन करें या घटना पर रिपोर्ट सहेजने के लिए टैप करें।',
      'volunteer_triage_show_qr': 'QR दिखाएँ',
      'volunteer_triage_tap_report': 'रिपोर्ट',
      'volunteer_triage_qr_title': 'इंसिडेंट हैंडऑफ़ QR',
      'volunteer_triage_qr_body': 'संरचित पेलोड के लिए स्टाफ़ या EMS के साथ साझा करें।',
      'volunteer_triage_report_saved': 'रिपोर्ट इस घटना के तहत सहेजी गई।',
      'volunteer_triage_report_failed': 'रिपोर्ट सहेजी नहीं जा सकी: ',
      'volunteer_victim_medical_offline_hint':
          'SOS पैकेट से — ऑफ़लाइन होने पर डिवाइस कैश से उपलब्ध।',
      'volunteer_victim_consciousness_title': 'चेतना',
      'volunteer_victim_three_questions': 'प्रारंभिक पीड़ित उत्तर',
      'volunteer_major_updates_log': 'केवल प्रमुख अपडेट',
      'volunteer_more_triage_details': 'अधिक ट्रायेज और वाइटल्स',
      'volunteer_more_victim_details': 'अधिक पीड़ित विवरण',
      'volunteer_sos_intake_title': 'SOS इनटेक (पीड़ित ऐप)',
      'volunteer_show_full_qa': 'पूर्ण Q&A देखें',
      'volunteer_full_qa_sheet_title': 'पीड़ित सुरक्षा Q&A (पूर्ण)',
      'volunteer_victim_label_conscious': 'चेतना',
      'volunteer_victim_label_breathing': 'साँस',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'टियर {tier} तक बढ़ा रहे हैं। अस्पताल {hospital} आज़मा रहे हैं।',
      'volunteer_dispatch_trying_hospital': 'अस्पताल {hospital} आज़मा रहे हैं।',
      'volunteer_dispatch_hospital_accepted':
          'अस्पताल {hospital} ने आपात स्थिति स्वीकार कर ली है। एम्बुलेंस समन्वय जारी है।',
      'volunteer_dispatch_all_hospitals_notified':
          'सभी अस्पतालों को सूचित किया गया। आपात सेवाओं तक बढ़ाया जा रहा है।',
      'sos_dispatch_alerting_nearest_trying':
          'आपके क्षेत्र के निकटतम अस्पताल को सूचित किया जा रहा है। {hospital} से संपर्क कर रहे हैं।',
      'sos_dispatch_escalating_tier_trying':
          'कोई जवाब नहीं। टियर {tier} तक बढ़ा रहे हैं। {hospital} आज़मा रहे हैं।',
      'sos_dispatch_retry_previous_trying':
          'पिछले अस्पताल से कोई जवाब नहीं। {hospital} आज़मा रहे हैं।',
      'sos_dispatch_all_hospitals_call_112':
          'सभी अस्पतालों को सूचित किया गया। आपात सेवाओं के लिए कृपया 112 पर कॉल करें।',
      'profile_synced': 'सिंक हो गया',
      'profile_not_synced': 'सिंक नहीं',
      'profile_saving': 'सहेज रहा है…',
      'profile_queued_offline': 'कतार में (ऑफ़लाइन)',
      'profile_save_failed': 'सहेजना विफल',
      'profile_save_timed_out': 'समय समाप्त',
      'profile_time_just_now': 'अभी',
      'profile_time_min_ago': '{n} मि पहले',
      'profile_time_hours_ago': '{n} घं पहले',
      'profile_time_days_ago': '{n} दिन पहले',
      'profile_db_unreachable':
          'डेटाबेस तक नहीं पहुँच सके। क्या Cloud Firestore चालू है?',
      'profile_saved_offline_msg': 'स्थानीय रूप से सहेजा — ऑनलाइन होने पर सिंक होगा।',
      'profile_saved_msg': 'चिकित्सा जानकारी सहेजी गई।',
      'profile_save_timeout_msg':
          'सहेजना समय समाप्त। इंटरनेट या Firebase कंसोल जाँचें।',
      'profile_save_error': 'सहेजने में त्रुटि: {e}',
      'profile_pin_saved_offline': 'पिन स्थानीय सहेजा — ऑनलाइन होने पर सिंक होगा।',
      'profile_pin_saved': 'SOS पिन सहेजा गया।',
      'profile_pin_save_error': 'SOS पिन सहेज नहीं सका: {e}',
      'drill_profile_banner':
          'अभ्यास प्रोफ़ाइल — लेआउट वैसा ही; साइन इन होने पर यहाँ के बदलाव आपके खाते में सहेजे जाते हैं।',
      'profile_sms_contact_title': 'इस संपर्क को आपातकालीन अपडेट भेजें (SMS)',
      'profile_sms_contact_subtitle':
          'जब प्रतिक्रियाकर्ता स्वीकार करें या ETA बदले, EmergencyOS आपके आपातकालीन संपर्क को SMS भेज सकता है।',
      'profile_dispatch_desk_title': 'मैं आपातकालीन डिस्पैच हूँ (Lifeline WebRTC)',
      'profile_dispatch_desk_subtitle':
          'केवल आधिकारिक EMS/डिस्पैच खातों के लिए। सक्रिय स्वयंसेवक घटनाओं पर Lifeline में डिस्पैच के रूप में शामिल होने देता है।',
      'profile_pin_status_set': 'पिन सेट है',
      'profile_pin_status_unset': 'पिन सेट नहीं',
      'profile_change_pin_btn': 'पिन बदलें',
      'profile_set_pin_btn': 'पिन सेट करें',
      'profile_pin_exit_note':
          'SOS सक्रिय स्क्रीन से बाहर निकलने और SOS रद्द/सुलझाने के लिए यह पिन ज़रूरी है।',
      'profile_hint_blood_type': 'उदा. O+',
      'profile_hint_allergies': 'उदा. पेनिसिलिन, मूँगफली',
      'profile_hint_conditions': 'उदा. अस्थमा, मधुमेह',
      'profile_hint_contact_name': 'नाम',
      'profile_hint_relationship': 'उदा. जीवनसाथी, माता-पिता',
      'profile_hint_phone': '+91 98765 43210',
      'profile_hint_medications': 'उदा. इंसुलिन',
      'profile_hint_donor': 'हाँ / नहीं',
      'home_duty_heading': 'आज की ड्यूटी',
      'home_duty_progress': '{done}/{total} पूर्ण',
      'home_map_semantics': 'आपका परिचालन क्षेत्र और वर्तमान स्थान दिखाने वाला मानचित्र',
      'home_recenter_map': 'मानचित्र को अपने स्थान पर केंद्रित करें',
      'home_sos_large_fab_hint': 'आपातकालीन अलर्ट भेजने के लिए SOS उलटी गिनती खोलें',
      'home_sos_cancelled_snack': 'SOS रद्द।',
      'home_sos_sent_snack': 'SOS भेजा गया! आपात सेवाएँ सूचित।',
      'quick_sos_title': 'त्वरित SOS',
      'quick_sos_subtitle': 'उत्तर दें — विवरण के साथ मदद तेज़ी से पहुँचती है',
      'quick_sos_practice_banner':
          'अभ्यास मार्गदर्शित इनटेक — सबमिट वास्तविक SOS नहीं बनाएगा। ड्रिल के लिए होम पर लाल SOS 3 सेकंड दबाएँ।',
      'quick_sos_section_what': 'आपातकाल क्या है?',
      'quick_sos_section_someone_else': 'क्या आप किसी और के लिए SOS ट्रिगर कर रहे हैं?',
      'quick_sos_send_now': 'अभी SOS भेजें',
      'quick_sos_select_first': 'आपातकाल चुनें और पुष्टि करें',
      'quick_sos_section_victim': 'पीड़ित की स्थिति',
      'quick_sos_victim_subtitle': 'प्रतिक्रियाकर्ताओं को सही उपकरण तैयार करने में मदद करता है',
      'quick_sos_section_people': 'कितने लोगों को मदद चाहिए?',
      'quick_sos_yes_someone_else': 'हाँ — किसी और के लिए',
      'quick_sos_no_for_me': 'नहीं — मेरे लिए',
      'quick_sos_other_hint': 'संक्षेप में अपनी स्थिति बताएँ...',
      'quick_sos_close': 'त्वरित SOS बंद करें',
      'quick_sos_drill_submit_disabled':
          'अभ्यास: सबमिट अक्षम। ड्रिल के लिए होम पर लाल SOS 3 सेकंड दबाएँ।',
      'quick_sos_failed': 'SOS विफल: {detail}',
      'quick_sos_could_not_start': 'SOS शुरू नहीं हो सका। पुनः प्रयास करें।',
      'quick_sos_victim_conscious_q': 'क्या व्यक्ति होश में है?',
      'quick_sos_victim_breathing_q': 'क्या व्यक्ति साँस ले रहा है?',
      'quick_sos_label_yes': 'हाँ',
      'quick_sos_label_no': 'नहीं',
      'quick_sos_label_unsure': 'पक्का नहीं',
      'quick_sos_person': 'व्यक्ति',
      'quick_sos_people': 'लोग',
      'quick_sos_people_three_plus': '3+',
      'login_tagline': 'आइए जानें बचाएँ',
      'login_subtitle':
          'आपातकाल रिपोर्ट करें, स्वयंसेवकों के साथ समन्वय करें, गोल्डन ऑवर में जानें बचाएँ।',
      'login_continue_google': 'Google से जारी रखें',
      'login_continue_phone': 'फ़ोन से जारी रखें',
      'login_send_code': 'सत्यापन कोड भेजें',
      'login_verify_login': 'सत्यापित करें और लॉग इन',
      'login_phone_label': 'फ़ोन नंबर',
      'login_phone_hint': '+919876543210',
      'login_otp_label': 'सत्यापन कोड (OTP)',
      'login_back_options': 'विकल्पों पर वापस',
      'login_change_phone': 'फ़ोन नंबर बदलें',
      'login_drill_mode': 'ड्रिल मोड',
      'login_drill_subtitle': 'अभ्यास के लिए टैप करें — कोई वास्तविक SOS नहीं',
      'login_drill_semantics': 'ड्रिल मोड, वास्तविक आपातकाल के बिना अभ्यास',
      'login_practise_victim': 'पीड़ित के रूप में अभ्यास',
      'login_practise_volunteer': 'स्वयंसेवक के रूप में अभ्यास',
      'login_admin_note':
          'मास्टर कंसोल: अलग खाता नहीं — नीचे टैप करें। साइन इन नहीं होने पर हल्का अनाम सत्र।',
      'login_ems_dashboard': 'EMS डैशबोर्ड',
      'login_emergency_operator': 'आपातकालीन सेवा ऑपरेटर लॉग इन',
      'ai_assist_practice_banner':
          'अभ्यास Lifeline — वास्तविक डिस्पैच पर कुछ नहीं जाता।',
      'ai_assist_rail_semantics': 'Lifeline स्तर {n}: {title}',
      'ai_assist_emergency_toggle_on': 'आपातकालीन मोड चालू, तत्काल मार्गदर्शन',
      'ai_assist_emergency_toggle_off': 'आपातकालीन मोड बंद',
      'dashboard_exit_drill_title': 'ड्रिल मोड से बाहर?',
      'dashboard_exit_drill_body':
          'आप अभ्यास सत्र से साइन आउट होंगे और लॉगिन पर लौटेंगे।',
      'dashboard_back_login_tooltip': 'लॉगिन पर वापस',
      'dashboard_exit_drill_confirm': 'बाहर निकलें',
      'sos_active_title_big': 'सक्रिय SOS',
      'sos_active_help_coming': 'मदद आ रही है। शांत रहें।',
      'sos_active_badge_waiting': 'प्रतीक्षा',
      'sos_active_badge_en_route_count': '{n} रास्ते में',
      'sos_active_mini_ambulance': 'एम्बुलेंस',
      'sos_active_mini_on_scene': 'मौके पर',
      'sos_active_mini_status': 'स्थिति',
      'sos_active_volunteers_count_short': '{n} स्वयंसेवक',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title': 'सभी अस्पतालों को सूचित किया गया',
      'sos_active_all_hospitals_notified_subtitle':
          'समय पर कोई अस्पताल स्वीकार नहीं हुआ। डिस्पैच आपातकालीन सेवाओं को आगे बढ़ा रहा है।',
      'sos_active_position_refresh_note':
          'बैटरी बचाने के लिए SOS के दौरान आपकी लोकेशन लगभग हर 45 सेकंड में अपडेट होती है। ऐप खुला रखें और हो सके तो चार्जर लगाएं।',
      'sos_active_mic_active': 'माइक · सक्रिय',
      'sos_active_mic_active_detail':
          'लाइव चैनल आपका माइक्रोफ़ोन सुन रहा है।',
      'sos_active_mic_standby': 'माइक · तैयार',
      'sos_active_mic_standby_detail': 'वॉइस चैनल की प्रतीक्षा…',
      'sos_active_mic_connecting': 'माइक · जुड़ रहा है',
      'sos_active_mic_connecting_detail': 'आपातकालीन वॉइस चैनल से जुड़ रहे हैं…',
      'sos_active_mic_reconnecting': 'माइक · फिर जुड़ रहा है',
      'sos_active_mic_reconnecting_detail': 'लाइव ऑडियो पुनः स्थापित…',
      'sos_active_mic_failed': 'माइक · बाधित',
      'sos_active_mic_failed_detail':
          'वॉइस चैनल उपलब्ध नहीं। ऊपर से पुनः प्रयास करें।',
      'sos_active_mic_ptt_only': 'माइक · घटना चैनल',
      'sos_active_mic_ptt_only_detail':
          'ऑप्स कंसोल ने Firebase PTT से वॉइस रूट किया। जवाबदारों तक पहुँचने के लिए ब्रॉडकास्ट दबाकर रखें।',
      'sos_active_mic_interrupted': 'माइक · रुका',
      'sos_active_mic_interrupted_detail':
          'ऐप ऑडियो प्रोसेस कर रहा है, थोड़ी देर रुकावट।',
      'sos_active_consciousness_note':
          'होश की जांच का उत्तर हाँ या ना से दें; अन्य प्रॉम्प्ट स्क्रीन के विकल्प का उपयोग करते हैं।',
      'sos_active_live_updates_header': 'लाइव अपडेट',
      'sos_active_live_updates_subtitle': 'डिस्पैच, स्वयंसेवक और डिवाइस',
      'sos_active_live_tag': 'लाइव',
      'sos_active_activity_log': 'गतिविधि लॉग',
      'sos_active_header_stat_coordinating_crew': 'टीम समन्वय',
      'sos_active_header_stat_coordinating': 'समन्वय',
      'sos_active_header_stat_en_route': 'मार्ग पर',
      'sos_active_header_stat_route_min': '~{n} मिनट',
      'sos_active_live_sos_is_live_title': 'SOS सक्रिय है',
      'sos_active_live_sos_is_live_detail':
          'आपकी लोकेशन और मेडिकल फ़्लैग आपातकालीन नेटवर्क पर हैं।',
      'sos_active_live_volunteers_notified_title': 'स्वयंसेवक सूचित',
      'sos_active_live_volunteers_notified_detail':
          'पास के स्वयंसेवकों को यह घटना रीयल टाइम में मिल रही है।',
      'sos_active_live_bridge_connected_title':
          'आपातकालीन वॉइस ब्रिज जुड़ा',
      'sos_active_live_bridge_connected_detail':
          'डिस्पैच डेस्क और जवाबदार इस चैनल को सुन सकते हैं।',
      'sos_active_live_ptt_title': 'Firebase PTT के माध्यम से आवाज़',
      'sos_active_live_ptt_detail':
          'इस फ़्लीट के लिए लाइव WebRTC ब्रिज बंद है। आवाज़ और टेक्स्ट अपडेट के लिए ब्रॉडकास्ट उपयोग करें।',
      'sos_active_live_contacts_notified_title':
          'आपातकालीन संपर्क सूचित',
      'sos_active_live_hospital_accepted_title': 'अस्पताल ने स्वीकार किया',
      'sos_active_live_ambulance_unit_assigned_title':
          'एम्बुलेंस यूनिट नियुक्त',
      'sos_active_live_ambulance_unit_assigned_subtitle': 'यूनिट {unit}',
      'sos_active_live_ambulance_en_route_title': 'एम्बुलेंस रास्ते में',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'रास्ते में',
      'sos_active_live_ambulance_en_route_route_eta': '~{n} मिनट (मार्ग)',
      'sos_active_live_ambulance_coordination_title': 'एम्बुलेंस समन्वय',
      'sos_active_live_ambulance_coordination_pending':
          'अस्पताल ने स्वीकार किया — एम्बुलेंस ऑपरेटरों को सूचना।',
      'sos_active_live_ambulance_coordination_arranging':
          'एम्बुलेंस क्रू की व्यवस्था — यूनिट रवाना होने पर मिनट ETA।',
      'sos_active_live_responder_status_title': 'जवाबदार स्थिति',
      'sos_active_live_volunteer_accepted_single_title': 'स्वयंसेवक स्वीकार',
      'sos_active_live_volunteer_accepted_many_title': 'स्वयंसेवक स्वीकार',
      'sos_active_live_volunteer_accepted_single_detail':
          'एक जवाबदार नियुक्त है और आपकी मदद के लिए आ रहा है।',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} जवाबदार इस SOS पर नियुक्त हैं।',
      'sos_active_live_volunteer_on_scene_single_title':
          'स्वयंसेवक मौके पर पहुँचा',
      'sos_active_live_volunteer_on_scene_many_title': 'स्वयंसेवक मौके पर',
      'sos_active_live_volunteer_on_scene_single_detail':
          'कोई आपके साथ या आपकी पिन पर है।',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} जवाबदार मौके पर चिह्नित।',
      'sos_active_live_responder_location_title': 'लाइव जवाबदार स्थान',
      'sos_active_live_responder_location_detail':
          'नियुक्त स्वयंसेवक का GPS मानचित्र पर अपडेट हो रहा है।',
      'sos_active_live_professional_dispatch_title':
          'पेशेवर डिस्पैच सक्रिय',
      'sos_active_live_professional_dispatch_detail':
          'समन्वित सेवाएँ इस घटना पर काम कर रही हैं।',
      'sos_active_ambulance_200m_detail':
          'एम्बुलेंस मौके पर — लगभग 200 मीटर के भीतर।',
      'sos_active_ambulance_200m_semantic_label':
          'एम्बुलेंस लगभग दो सौ मीटर के भीतर मौके पर',
      'sos_active_bridge_channel_on_suffix': ' · {n} चैनल पर',
      'sos_active_bridge_channel_voice': 'आपातकालीन वॉइस चैनल',
      'sos_active_bridge_channel_ptt': 'आपातकालीन चैनल · Firebase PTT',
      'sos_active_bridge_channel_failed': 'आपातकालीन चैनल · पुनः प्रयास करें',
      'sos_active_bridge_channel_connecting':
          'आपातकालीन चैनल · जुड़ रहा है',
      'sos_active_dispatch_contact_hospitals_default':
          'हम आपकी लोकेशन और आपातकालीन प्रकार के आधार पर पास के अस्पतालों से संपर्क कर रहे हैं।',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'एम्बुलेंस क्रू सूचित',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'साझेदार अस्पताल ने आपका केस स्वीकार किया। एम्बुलेंस ऑपरेटरों को सूचित किया जा रहा है।',
      'sos_active_dispatch_ambulance_confirmed_title': 'एम्बुलेंस पुष्टि',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'यूनिट {unit} रास्ते में है। वहीं रहें जहाँ जवाबदार पहुँच सकें।',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'एक एम्बुलेंस रास्ते में है। वहीं रहें जहाँ जवाबदार पहुँच सकें।',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'एम्बुलेंस हैंडऑफ में देरी',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'अस्पताल ने स्वीकार किया, परन्तु समय पर कोई एम्बुलेंस क्रू पुष्टि नहीं। डिस्पैच बढ़ा रहा है — ज़रूरत हो तो 112 पर कॉल करें।',
      'sos_active_dispatch_pending_title_trying': 'प्रयास: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · अस्पताल प्रतिक्रिया की प्रतीक्षा।',
      'sos_active_dispatch_accepted_title': '{hospital} ने स्वीकार किया',
      'sos_active_dispatch_accepted_subtitle':
          'एम्बुलेंस डिस्पैच का समन्वय किया जा रहा है।',
      'sos_active_dispatch_exhausted_title': 'सभी अस्पताल सूचित',
      'sos_active_dispatch_exhausted_subtitle':
          'समय पर कोई अस्पताल स्वीकार नहीं हुआ। डिस्पैच आपातकालीन सेवाओं को आगे बढ़ा रहा है।',
      'sos_active_dispatch_generic_title': 'अस्पताल डिस्पैच',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'आपातकालीन वॉइस चैनल',
      'volunteer_bridge_join_hint_incident':
          'जुड़ाव इस घटना का उपयोग करता है: यदि आपका नंबर मेल खाता है तो आपातकालीन संपर्क; अन्यथा स्वीकृत स्वयंसेवक।',
      'volunteer_bridge_join_hint_elite':
          'जब आप स्वीकृत जवाबदार हों तो जुड़ाव आपकी एलीट स्वयंसेवक पहुँच का उपयोग करता है; अन्यथा संपर्क यदि आपका नंबर मेल खाता है।',
      'volunteer_bridge_join_hint_desk':
          'आप आपकी प्रोफ़ाइल पर आपातकालीन सेवा डेस्क के रूप में डिस्पैच के तौर पर जुड़ते हैं।',
      'volunteer_bridge_join_voice_btn': 'वॉइस में शामिल हों',
      'volunteer_bridge_connecting_btn': 'जुड़ रहा है…',
      'volunteer_bridge_incident_id_hint': 'घटना ID',
      'volunteer_consignment_live_location_hint':
          'जब आप कंसाइनमेंट पर हैं, आपकी लाइव लोकेशन इस घटना से साझा है ताकि नक्शा और ETA सटीक रहे।',
      'volunteer_consignment_low_power_label': 'लो पावर',
      'volunteer_consignment_normal_gps_label': 'सामान्य GPS',
      'bridge_card_incident_id_missing': 'घटना आईडी गुम है।',
      'bridge_card_ptt_only_snackbar':
          'ऑपरेशन कंसोल ने पीड़ित की आवाज़ Firebase PTT से भेजी। WebRTC ब्रिज जुड़ाव अक्षम है।',
      'bridge_card_ptt_only_banner':
          'कंसोल ने Firebase PTT से आवाज़ भेजी — इस फ़्लीट के लिए LiveKit ब्रिज जुड़ाव अक्षम है।',
      'bridge_card_connected_snackbar': 'वॉइस चैनल से जुड़ गए।',
      'bridge_card_could_not_join': 'जुड़ नहीं सके: {err}',
      'bridge_card_voice_channel_title': 'वॉइस चैनल',
      'bridge_card_calm_disclaimer':
          'शांत रहें और स्पष्ट बोलें। स्थिर स्वर पीड़ित और अन्य उत्तरदाताओं की मदद करता है। चिल्लाएं नहीं और शब्दों को जल्दबाज़ी से न बोलें।',
      'bridge_card_cancel': 'रद्द करें',
      'bridge_card_join_voice': 'वॉइस में शामिल हों',
      'bridge_card_voice_connected': 'वॉइस जुड़ा',
      'bridge_card_in_channel': '{n} चैनल में',
      'bridge_card_transmitting': 'प्रसारण हो रहा है…',
      'bridge_card_hold_to_talk': 'बात करने के लिए दबाए रखें',
      'bridge_card_disconnect': 'डिस्कनेक्ट करें',
      'vol_ems_banner_en_route': 'एम्बुलेंस घटनास्थल की ओर',
      'vol_ems_banner_on_scene': 'एम्बुलेंस स्थान पर (~200 मी)',
      'vol_ems_banner_returning': 'एम्बुलेंस अस्पताल लौट रही है',
      'vol_ems_banner_complete': 'प्रतिक्रिया पूरी · एम्बुलेंस स्टेशन पर',
      'vol_ems_banner_complete_with_cycle':
          'प्रतिक्रिया पूरी · एम्बुलेंस स्टेशन पर · कुल चक्र {m}मि {s}से',
      'vol_tooltip_lifeline_first_aid':
          'लाइफलाइन — प्राथमिक उपचार मार्गदर्शिका (प्रतिक्रिया पर रहता है)',
      'vol_tooltip_exit_mission': 'मिशन समाप्त',
      'vol_low_power_tracking_hint':
          'कम-पावर ट्रैकिंग: हम आपकी स्थिति कम बार और केवल बड़ी गति के बाद सिंक करते हैं। डिस्पैच अब भी आपका अंतिम बिंदु देखता है।',
      'vol_marker_you': 'आप',
      'vol_marker_active_unit': 'सक्रिय यूनिट',
      'vol_marker_practice_incident': 'अभ्यास घटना',
      'vol_marker_accident_scene': 'दुर्घटना स्थल',
      'vol_marker_training_pin': 'प्रशिक्षण पिन — वास्तविक SOS नहीं',
      'vol_marker_high_severity': 'GITM कॉलेज - उच्च गंभीरता',
      'vol_marker_accepted_hospital': 'स्वीकृत: {hospital}',
      'vol_marker_trying_hospital': 'कोशिश: {hospital}',
      'vol_marker_ambulance_on_scene': 'एम्बुलेंस स्थान पर!',
      'vol_marker_ambulance_en_route': 'एम्बुलेंस मार्ग पर',
      'vol_badge_at_scene_pin': 'स्थान पिन पर',
      'vol_badge_in_5km_zone': '5 किमी क्षेत्र में',
      'vol_badge_en_route': 'मार्ग पर',
    },

    // ── Tamil (தமிழ்) ──────────────────────────────────────────────────────
    'ta': {
      'app_name': 'EmergencyOS',
      'profile_title': 'சுயவிவரம் & மருத்துவ அடையாளம்',
      'language': 'மொழி',
      'save_medical_profile': 'மருத்துவ விவரம் சேமி',
      'critical_medical_info': 'முக்கிய மருத்துவ தகவல்',
      'emergency_contacts': 'அவசர தொடர்புகள்',
      'golden_hour_details': 'கோல்டன் ஹவர் விவரங்கள்',
      'sos_lock': 'SOS பூட்டு',
      'top_life_savers': 'சிறந்த உயிர் காப்பாளர்கள்',
      'lives_saved': 'காப்பாற்றிய உயிர்கள்',
      'active_alerts': 'செயலில் உள்ள எச்சரிக்கைகள்',
      'rank': 'தரவரிசை',
      'on_duty': 'பணியில்',
      'standby': 'காத்திருப்பு',
      'sos': 'SOS',
      'call_now': 'இப்போது அழைக்கவும்',
      'quick_guide': 'விரைவு வழிகாட்டி',
      'detailed_instructions': 'விரிவான வழிமுறைகள்',
      'red_flags': 'ஆபத்து அறிகுறிகள்',
      'cautions': 'எச்சரிக்கைகள்',
      'voice_walkthrough': 'குரல் வழிகாட்டுதல்',
      'playing': 'இயங்குகிறது...',
      'swipe_next_guide': 'அடுத்த வழிகாட்டிக்கு ஸ்வைப் செய்யவும்',
      'watch_video_guide': 'முழு வீடியோ வழிகாட்டியைப் பாருங்கள்',
      'emergency_grid_scan': 'அவசர கிரிட் ஸ்கேன்',
      'area_telemetry': 'பகுதி டெலிமெட்ரி & ஆபத்து குறியீடு',
      'report_hazard': 'ஆபத்தைப் புகாரளிக்கவும்',
      'todays_duty': 'இன்றைய கடமை',
      'blood_type': 'இரத்த வகை',
      'allergies': 'ஒவ்வாமைகள்',
      'medical_conditions': 'மருத்துவ நிலைகள்',
      'contact_name': 'முதன்மை தொடர்பு பெயர்',
      'contact_phone': 'முதன்மை தொடர்பு எண்',
      'relationship': 'உறவு',
      'medications': 'தற்போதைய மருந்துகள்',
      'organ_donor': 'உறுப்பு தான நிலை',
      'good_morning': 'காலை வணக்கம்,',
      'good_afternoon': 'மதிய வணக்கம்,',
      'good_evening': 'மாலை வணக்கம்,',
      'hospitals': 'மருத்துவமனைகள்',
      'visual_walkthrough': 'காட்சி வழிகாட்டுதல்',
      'lifeline': 'லைஃப்லைன்',
      'nav_home': 'முகப்பு',
      'nav_map': 'வரைபடம்',
      'nav_grid': 'கிரிட்',
      'nav_profile': 'சுயவிவரம்',
      'map_caching_offline_pct': 'ஆஃப்லைனுக்கு பகுதி தற்காலிகச் சேமிப்பு — {pct}%',
      'map_drill_practice_banner':
          'பயிற்சி கிரிட்: துடிக்கும் பின்கள் = டெமோ செயலில் எச்சரிக்கைகள். அடுக்குகளுக்கு வரைபட வடிகட்டிகள் — உண்மையான தரவு அல்ல.',
      'map_recenter_tooltip': 'மீண்டும் மையப்படுத்து',
      'map_legend_hospital': 'மருத்துவமனை',
      'map_legend_live_sos_history': 'நேரடி SOS / வரலாறு',
      'map_legend_past_this_hex': 'கடந்த (இந்த ஹெக்ஸ்)',
      'map_legend_in_area': 'பகுதியில் {n}',
      'map_legend_in_cell': 'செல்லில் {n}',
      'map_legend_volunteers_on_duty': 'கடமையில் தன்னார்வலர்கள்',
      'map_legend_volunteers_in_grid': 'கிரிட்டில் {n}',
      'map_legend_responder_scene': 'பதிலளிப்பாளர் → இடம்',
      'map_responder_routes_one': '{n} பாதை',
      'map_responder_routes_many': '{n} பாதைகள்',
      'map_filters_title': 'வரைபட வடிகட்டிகள்',
      'step_prefix': 'படி',
      'highlights_steps': 'ஒவ்வொன்றாக படிகளை காட்டுகிறது',
      'offline_mode': 'ஆஃப்லைன் — நெட்வொர்க் துண்டிக்கப்பட்டது',
      'volunteer': 'தன்னார்வலர்',
      'unranked': 'தரவரிசை இல்லை',
      'live': 'நேரலை',
      'you': 'நீங்கள்',
      'saved': 'காப்பாற்றியது',
      'xp_responses': 'XP · {0} பதில்கள்',
      'duty_monitoring': 'நீங்கள் பணியில் இருக்கும்போது SOS பாப்-அப்கள் இயக்கத்தில் உள்ளன.',
      'turn_on_duty_msg': 'SOS பாப்-அப்கள் பெற பணியை இயக்கவும்.',
      'on_duty_snack': 'பணியில் — உங்கள் பகுதியில் சம்பவங்களை கண்காணிக்கிறது...',
      'off_duty_snack': 'காத்திருப்பு — பணி அமர்வு பதிவு செய்யப்பட்டது.',
      'leaderboard_offline': 'லீடர்போர்டு ஆஃப்லைன்',
      'leaderboard_offline_sub': 'ஒத்திசைவு நிறுத்தப்பட்டது. கேச் செய்யப்பட்ட மதிப்பெண்கள்.',
      'set_sos_pin_first': 'முதலில் SOS பின் அமைக்கவும்',
      'set_pin_safety_msg': 'பாதுகாப்பிற்காக, SOS உருவாக்கும் முன் பின் அமைக்க வேண்டும்.',
      'set_pin_now': 'இப்போது பின் அமை',
      'later': 'பின்னர்',
      'sos_screen_title': 'SOS',
      'sos_hold_banner': 'அவசரத்தை அனுப்ப 3 வினாடிகள் அழுத்திப் பிடிக்கவும்.',
      'sos_hold_button': 'SOS ஐ அனுப்ப அழுத்திப் பிடிக்கவும்',
      'sos_semantics_hold_hint': 'SOS. அனுப்ப மூன்று வினாடிகள் அழுத்திப் பிடிக்கவும்.',
      'home_duty_heading': 'இன்றைய கடமை',
      'home_duty_progress': '{done}/{total} முடிந்தது',
      'home_map_semantics': 'உங்கள் பகுதி மற்றும் இருப்பிடத்தைக் காட்டும் வரைபடம்',
      'home_recenter_map': 'வரைபடத்தை உங்கள் இருப்பிடத்திற்கு மையப்படுத்து',
      'home_sos_large_fab_hint': 'அவசர எச்சரிக்கைக்கு SOS எண்ணிக்கையைத் திற',
      'home_sos_cancelled_snack': 'SOS ரத்து.',
      'home_sos_sent_snack': 'SOS அனுப்பப்பட்டது! அவசர சேவைகளுக்குத் தெரிவிக்கப்பட்டது.',
      'quick_sos_title': 'விரைவு SOS',
      'quick_sos_subtitle': 'பதிலளிக்கவும் — விவரங்களுடன் உதவி விரைவாக வரும்',
      'quick_sos_practice_banner':
          'பயிற்சி வழிகாட்டப்பட்ட உள்வாங்கல் — சமர்ப்பிப்பு உண்மையான SOS ஐ உருவாக்காது.',
      'quick_sos_section_what': 'அவசரம் என்ன?',
      'quick_sos_section_someone_else': 'வேறொருவருக்காக SOS ஐத் தூண்டுகிறீர்களா?',
      'quick_sos_send_now': 'இப்போது SOS அனுப்பு',
      'quick_sos_select_first': 'அவசரத்தைத் தேர்ந்தெடுத்து உறுதிப்படுத்தவும்',
      'quick_sos_section_victim': 'பாதிக்கப்பட்டவர் நிலை',
      'quick_sos_victim_subtitle': 'பதிலளிப்பவர்கள் சரியான உபகரணங்களைத் தயார் செய்ய உதவுகிறது',
      'quick_sos_section_people': 'எத்தனை பேருக்கு உதவி தேவை?',
      'quick_sos_yes_someone_else': 'ஆம் — வேறொருவருக்காக',
      'quick_sos_no_for_me': 'இல்லை — எனக்காக',
      'quick_sos_other_hint': 'உங்கள் நிலையை சுருக்கமாக விவரிக்கவும்...',
      'quick_sos_close': 'விரைவு SOS மூடு',
      'quick_sos_drill_submit_disabled':
          'பயிற்சி: சமர்ப்பிப்பு முடக்கப்பட்டது. ட்ரிலுக்கு முகப்பில் சிவப்பு SOS 3 வி. அழுத்தவும்.',
      'quick_sos_failed': 'SOS தோல்வி: {detail}',
      'quick_sos_could_not_start': 'SOS தொடங்க முடியவில்லை. மீண்டும் முயலவும்.',
      'quick_sos_victim_conscious_q': 'அந்த நபர் உணர்வுடன் உள்ளாரா?',
      'sos_are_you_conscious':
          'நீங்கள் உணர்வுடன் உள்ளீர்களா? தயவுசெய்து ஆம் அல்லது இல்லை என்று பதிலளிக்கவும்.',
      'sos_tts_opening_guidance':
          'உங்கள் SOS செயலில் உள்ளது. உதவி வருகிறது. பேசும் வழிமுறைகளைப் பின்பற்றி பதிலளிக்க தட்டவும்.',
      'sos_interview_q1_prompt': 'என்ன நடக்கிறது? (அவசர வகை)',
      'sos_interview_q2_prompt': 'நீங்கள் பாதுகாப்பாக உள்ளீர்களா? எவ்வளவு serious?',
      'sos_interview_q3_prompt': 'எத்தனை பேர் ஈடுபட்டுள்ளனர்?',
      'sos_chip_cat_accident': 'விபத்து',
      'sos_chip_cat_medical': 'மருத்துவ',
      'sos_chip_cat_hazard': 'அபாயம் (தீ, மூழ்குதல், முதலியன)',
      'sos_chip_cat_assault': 'தாக்குதல்',
      'sos_chip_cat_other': 'மற்றவை',
      'sos_chip_safe_critical': 'மிக மோசமான (உயிருக்கு ஆபத்து)',
      'sos_chip_safe_injured': 'காயம்; நிலையானது',
      'sos_chip_safe_danger': 'காயமில்லை; ஆனால் ஆபத்தில்',
      'sos_chip_safe_safe_now': 'இப்போது பாதுகாப்பு',
      'sos_chip_people_me': 'நான் மட்டும்',
      'sos_chip_people_two': 'இருவர்',
      'sos_chip_people_many': 'இருவருக்கு மேல்',
      'sos_tts_interview_saved':
          'பாதிக்கப்பட்டவர் பேட்டி தரவு அனைத்தும் சேமிக்கப்பட்டது. மீட்பவர்களுக்கு விவரங்கள் உள்ளன. ஒவ்வொரு 60 வினாடியிலும் உணர்வு சோதனை தொடரும்.',
      'sos_tts_map_routes':
          'வரைபடத் தாவலைத் திறக்கவும்: சிவப்பு ஒதுக்கப்பட்ட மருத்துவமனைக்கு சாலை வழி; இல்லையெனில் அணுகல் பாதை. பச்சை தன்னார்வலர் வழி. அவசர குரல் சேனலில் இருங்கள்.',
      'sos_tts_emergency_contacts_on_file':
          'Your emergency contact from your profile is attached to this SOS. SMS updates may be sent when that option is enabled.',
      'sos_tts_conscious_no_answer_attempt':
          'பதில் இல்லை. உணர்வு சோதனை {max} இல் {n}. ஒரு நிமிடத்தில் மீண்டும் கேட்கிறோம்.',
      'voice_volunteer_accepted':
          'தொண்டர் ஏற்றுக்கொண்டார். உதவி வருகிறது.',
      'voice_ambulance_dispatched_eta':
          'ஆம்புலன்ஸ் அனுப்பப்பட்டது. மதிப்பிடப்பட்ட வருகை: {eta}.',
      'voice_police_dispatched_eta':
          'காவல்துறை அனுப்பப்பட்டது. மதிப்பிடப்பட்ட வருகை: {eta}.',
      'voice_ambulance_on_scene_victim':
          'ஆம்புலன்ஸ் இடத்தில் உள்ளது — உங்களிடமிருந்து சுமார் இருநூறு மீட்டர் தொலைவில்.',
      'voice_ambulance_on_scene_volunteer':
          'ஆம்புலன்ஸ் இடத்தில் உள்ளது — சம்பவ இடத்திலிருந்து சுமார் இருநூறு மீட்டர் தொலைவில்.',
      'voice_ambulance_returning': 'ஆம்புலன்ஸ் மருத்துவமனைக்குத் திரும்புகிறது.',
      'voice_response_complete_station':
          'பதில் முடிந்தது. ஆம்புலன்ஸ் நிலையத்தில்.',
      'voice_response_complete_cycle':
          'பதில் முடிந்தது. ஆம்புலன்ஸ் நிலையத்தில். மொத்த சுழற்சி {minutes} நிமிடங்கள் {seconds} விநாடிகள்.',
      'voice_volunteers_on_scene_count':
          '{n} தொண்டர்கள் இப்போது இடத்தில் உள்ளனர்.',
      'voice_one_volunteer_on_scene': 'ஒரு தொண்டர் இடத்தில் உள்ளார்.',
      'voice_ptt_joined_comms': '{who} குரல் தொடர்பில் சேர்ந்தார்.',
      'voice_tts_unavailable_banner':
          'குரல் வழிகாட்டுதல் கிடைக்கவில்லை — திரையில் உள்ள உரையைப் படிக்கவும்.',
      'language_picker_title': 'மொழி',
      'volunteer_victim_medical_card': 'பாதிக்கப்பட்டவர் மருத்துவ அட்டை',
      'volunteer_dispatch_milestone_title': 'டிஸ்பैச் புதுப்பிப்புகள்',
      'volunteer_dispatch_milestone_hospital': 'மருத்துவமனை ஏற்றுக்கொண்டது: {hospital}',
      'volunteer_dispatch_milestone_unit': 'ஆம்புலன்ஸ் யூனிட்: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'ஆம்புலன்ஸ் குழு: ஒருங்கிணைப்பு…',
      'volunteer_dispatch_milestone_en_route': 'ஆம்புலன்ஸ் வழியில்',
      'volunteer_triage_qr_report_title': 'QR அல்லது தட்டவும் அறிக்கை',
      'volunteer_triage_qr_report_subtitle':
          'கையளிப்புக்கு குறியீட்டை ஸ்கேன் செய்யவும் அல்லது சம்பவ அறிக்கையைச் சேமிக்க தட்டவும்.',
      'volunteer_triage_show_qr': 'QR காட்டு',
      'volunteer_triage_tap_report': 'அறிக்கை',
      'volunteer_triage_qr_title': 'சம்பவ கையளிப்பு QR',
      'volunteer_triage_qr_body': 'கட்டமைக்கப்பட்ட தரவுக்கு ஊழியர்கள் அல்லது EMS உடன் பகிரவும்.',
      'volunteer_triage_report_saved': 'அறிக்கை இந்த சம்பவத்தின் கீழ் சேமிக்கப்பட்டது.',
      'volunteer_triage_report_failed': 'அறிக்கையைச் சேமிக்க முடியவில்லை: ',
      'volunteer_victim_medical_offline_hint':
          'SOS பாக்கெட்டிலிருந்து — ஆஃப்லைனில் சாதன கேச் மூலம்.',
      'volunteer_victim_consciousness_title': 'உணர்வு',
      'volunteer_victim_three_questions': 'ஆரம்ப பாதிக்கப்பட்டவர் பதில்கள்',
      'volunteer_major_updates_log': 'முக்கியமான புதுப்பிப்புகள் மட்டும்',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'அடுக்கு {tier} வரை உயர்த்துகிறோம். மருத்துவமனை {hospital} முயற்சிக்கிறோம்.',
      'volunteer_dispatch_trying_hospital': 'மருத்துவமனை {hospital} முயற்சிக்கிறோம்.',
      'volunteer_dispatch_hospital_accepted':
          '{hospital} அவசரத்தை ஏற்றது. ஆம்புலன்ஸ் ஒருங்கிணைப்பு நடக்கிறது.',
      'volunteer_dispatch_all_hospitals_notified':
          'அனைத்து மருத்துவமனைகளுக்கும் அறிவிக்கப்பட்டது. அவசர சேவைகளுக்கு மேலே செல்கிறோம்.',
      'sos_dispatch_alerting_nearest_trying':
          'உங்கள் பகுதியில் அருகிலுள்ள மருத்துவமனையை அழைக்கிறோம். {hospital} முயற்சிக்கிறோம்.',
      'sos_dispatch_escalating_tier_trying':
          'பதில் இல்லை. அடுக்கு {tier} வரை உயர்த்துகிறோம். {hospital} முயற்சிக்கிறோம்.',
      'sos_dispatch_retry_previous_trying':
          'முந்தைய மருத்துவமனையில் இருந்து பதில் இல்லை. {hospital} முயற்சிக்கிறோம்.',
      'sos_dispatch_all_hospitals_call_112':
          'அனைத்து மருத்துவமனைகளுக்கும் அறிவிக்கப்பட்டது. அவசர சேவைகளுக்கு 112 ஐ அழைக்கவும்.',
      'quick_sos_victim_breathing_q': 'அந்த நபர் சுவாசிக்கிறாரா?',
      'quick_sos_label_yes': 'ஆம்',
      'quick_sos_label_no': 'இல்லை',
      'quick_sos_label_unsure': 'உறுதியில்லை',
      'quick_sos_person': 'நபர்',
      'quick_sos_people': 'நபர்கள்',
      'quick_sos_people_three_plus': '3+',
      'login_tagline': 'உயிர்களைக் காப்போம்',
      'login_subtitle':
          'அவசரங்களைப் புகாரளிக்கவும், தன்னார்வலர்களுடன் ஒருங்கிணைக்கவும், கோல்டன் ஹவரில் உயிர்களைக் காப்பாற்றவும்.',
      'login_continue_google': 'Google உடன் தொடரவும்',
      'login_continue_phone': 'தொலைபேசியுடன் தொடரவும்',
      'login_send_code': 'சரிபார்ப்புக் குறியீட்டை அனுப்பு',
      'login_verify_login': 'சரிபார்த்து உள்நுழை',
      'login_phone_label': 'தொலைபேசி எண்',
      'login_phone_hint': '+919876543210',
      'login_otp_label': 'சரிபார்ப்புக் குறியீடு (OTP)',
      'login_back_options': 'விருப்பங்களுக்குத் திரும்பு',
      'login_change_phone': 'தொலைபேசி எண்ணை மாற்று',
      'login_drill_mode': 'பயிற்சி பயன்முறை',
      'login_drill_subtitle': 'பயிற்சிக்குத் தட்டவும் — உண்மையான SOS இல்லை',
      'login_drill_semantics': 'பயிற்சி பயன்முறை, உண்மையான அவசரம் இல்லாமல்',
      'login_practise_victim': 'பாதிக்கப்பட்டவராக பயிற்சி',
      'login_practise_volunteer': 'தன்னார்வலராக பயிற்சி',
      'login_admin_note':
          'முதன்மை கன்சோல்: தனி கணக்கு இல்லை — கீழே தட்டவும். உள்நுழையாவிட்டால் இலகுவான அநாமதேய அமர்வு.',
      'login_ems_dashboard': 'EMS டாஷ்போர்டு',
      'login_emergency_operator': 'அவசர சேவை ஆபரேட்டர் உள்நுழைவு',
      'ai_assist_practice_banner':
          'பயிற்சி Lifeline — உண்மையான டிஸ்பैச் எதுவும் அனுப்பப்படாது.',
      'ai_assist_rail_semantics': 'Lifeline நிலை {n}: {title}',
      'ai_assist_emergency_toggle_on': 'அவசர பயன்முறை இயக்கம், அவசர வழிகாட்டுதல்',
      'ai_assist_emergency_toggle_off': 'அவசர பயன்முறை முடக்கம்',
      'dashboard_exit_drill_title': 'பயிற்சி பயன்முறையிலிருந்து வெளியேற?',
      'dashboard_exit_drill_body':
          'இந்த பயிற்சி அமர்விலிருந்து வெளியேறி உள்நுழைவு பக்கத்திற்குத் திரும்புவீர்கள்.',
      'dashboard_back_login_tooltip': 'உள்நுழைவுக்குத் திரும்பு',
      'sos_active_title_big': 'செயலில் உள்ள SOS',
      'sos_active_help_coming': 'உதவி வந்துகொண்டிருக்கிறது. அமைதியாக இருங்கள்.',
      'sos_active_badge_waiting': 'காத்திருக்கிறது',
      'sos_active_badge_en_route_count': '{n} வழியில்',
      'sos_active_mini_ambulance': 'ஆம்புலன்ஸ்',
      'sos_active_mini_on_scene': 'இடத்தில்',
      'sos_active_mini_status': 'நிலை',
      'sos_active_volunteers_count_short': '{n} தன்னார்வலர்',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title':
          'அனைத்து மருத்துவமனைகளுக்கும் அறிவிப்பு',
      'sos_active_all_hospitals_notified_subtitle':
          'நேரத்தில் எந்த மருத்துவமனையும் ஏற்கவில்லை. அனுப்பீடு அவசர சேவைகளுக்கு உயர்த்தப்படுகிறது.',
      'sos_active_position_refresh_note':
          'பேட்டரியை சேமிக்க SOS போது உங்கள் இருப்பிடம் சுமார் 45 வினாடிகளுக்கு ஒருமுறை புதுப்பிக்கப்படுகிறது. பயன்பாட்டை திறந்து வைத்து, முடிந்தால் சார்ஜில் இணையுங்கள்.',
      'sos_active_mic_active': 'மைக் · செயலில்',
      'sos_active_mic_active_detail':
          'நேரலை சேனல் உங்கள் மைக்ரோஃபோனை பெறுகிறது.',
      'sos_active_mic_standby': 'மைக் · காத்திருப்பு',
      'sos_active_mic_standby_detail': 'குரல் சேனலுக்காக காத்திருக்கிறது…',
      'sos_active_mic_connecting': 'மைக் · இணைக்கிறது',
      'sos_active_mic_connecting_detail':
          'அவசர குரல் சேனலுடன் இணைக்கிறது…',
      'sos_active_mic_reconnecting': 'மைக் · மீண்டும் இணைக்கிறது',
      'sos_active_mic_reconnecting_detail':
          'நேரலை ஆடியோவை மீட்டமைக்கிறது…',
      'sos_active_mic_failed': 'மைக் · தடங்கல்',
      'sos_active_mic_failed_detail':
          'குரல் சேனல் கிடைக்கவில்லை. மேலே RETRY பயன்படுத்தவும்.',
      'sos_active_mic_ptt_only': 'மைக் · சம்பவ சேனல்',
      'sos_active_mic_ptt_only_detail':
          'ஆபரேஷன்ஸ் கன்சோல் Firebase PTT வழியாக குரலை திருப்பியது. பதிலளிப்பவர்களை அடைய ப்ராட்காஸ்ட்டை பிடிக்கவும்.',
      'sos_active_mic_interrupted': 'மைக் · இடைநிறுத்தப்பட்டது',
      'sos_active_mic_interrupted_detail':
          'பயன்பாடு ஆடியோ செயலாக்கும் போது சிறிய இடைநிறுத்தம்.',
      'sos_active_consciousness_note':
          'நினைவு சரிபார்ப்புக்கு ஆம் அல்லது இல்லை என பதிலளிக்கவும்; மற்றவை திரை விருப்பங்களைப் பயன்படுத்துகின்றன.',
      'sos_active_live_updates_header': 'நேரலை புதுப்பிப்புகள்',
      'sos_active_live_updates_subtitle':
          'அனுப்பீடு, தன்னார்வலர் & சாதனம்',
      'sos_active_live_tag': 'நேரலை',
      'sos_active_activity_log': 'செயல்பாட்டு பதிவு',
      'sos_active_header_stat_coordinating_crew': 'குழு ஒருங்கிணைப்பு',
      'sos_active_header_stat_coordinating': 'ஒருங்கிணைப்பு',
      'sos_active_header_stat_en_route': 'வரும் வழியில்',
      'sos_active_header_stat_route_min': '~{n} நிமிடம்',
      'sos_active_live_sos_is_live_title': 'SOS நேரலையில் உள்ளது',
      'sos_active_live_sos_is_live_detail':
          'உங்கள் இருப்பிடம் மற்றும் மருத்துவ கொடிகள் அவசர நெட்வொர்க்கில் உள்ளன.',
      'sos_active_live_volunteers_notified_title':
          'தன்னார்வலர்களுக்கு அறிவிப்பு',
      'sos_active_live_volunteers_notified_detail':
          'அருகிலுள்ள தன்னார்வலர்கள் இந்த சம்பவத்தை நேரலையில் பெறுகின்றனர்.',
      'sos_active_live_bridge_connected_title':
          'அவசர குரல் பாலம் இணைக்கப்பட்டது',
      'sos_active_live_bridge_connected_detail':
          'அனுப்பீட்டு டெஸ்க் மற்றும் பதிலளிப்பவர்கள் இந்த சேனலைக் கேட்க முடியும்.',
      'sos_active_live_ptt_title': 'Firebase PTT வழி குரல்',
      'sos_active_live_ptt_detail':
          'இந்த கப்பலுக்கு நேரலை WebRTC பாலம் ஆஃப். குரல் மற்றும் உரை புதுப்பிப்புகளுக்கு ப்ராட்காஸ்ட்டைப் பயன்படுத்தவும்.',
      'sos_active_live_contacts_notified_title':
          'அவசர தொடர்புகளுக்கு அறிவிப்பு',
      'sos_active_live_hospital_accepted_title':
          'மருத்துவமனை ஏற்றுக்கொண்டது',
      'sos_active_live_ambulance_unit_assigned_title':
          'ஆம்புலன்ஸ் அலகு ஒதுக்கப்பட்டது',
      'sos_active_live_ambulance_unit_assigned_subtitle': 'அலகு {unit}',
      'sos_active_live_ambulance_en_route_title': 'ஆம்புலன்ஸ் வழியில்',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'வழியில்',
      'sos_active_live_ambulance_en_route_route_eta': '~{n} நிமிடம் (பாதை)',
      'sos_active_live_ambulance_coordination_title':
          'ஆம்புலன்ஸ் ஒருங்கிணைப்பு',
      'sos_active_live_ambulance_coordination_pending':
          'மருத்துவமனை ஏற்றுக்கொண்டது — ஆம்புலன்ஸ் ஆபரேட்டர்கள் அறிவிக்கப்படுகின்றனர்.',
      'sos_active_live_ambulance_coordination_arranging':
          'ஆம்புலன்ஸ் குழு ஏற்பாடு — அலகு வழியில் இருக்கும்போது நிமிட ETA.',
      'sos_active_live_responder_status_title': 'பதிலளிப்பாளர் நிலை',
      'sos_active_live_volunteer_accepted_single_title':
          'தன்னார்வலர் ஏற்றுக்கொண்டார்',
      'sos_active_live_volunteer_accepted_many_title':
          'தன்னார்வலர்கள் ஏற்றுக்கொண்டனர்',
      'sos_active_live_volunteer_accepted_single_detail':
          'ஒரு பதிலளிப்பாளர் ஒதுக்கப்பட்டு உங்களுக்கு வந்துகொண்டிருக்கிறார்.',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} பதிலளிப்பாளர்கள் இந்த SOS-க்கு ஒதுக்கப்பட்டுள்ளனர்.',
      'sos_active_live_volunteer_on_scene_single_title':
          'தன்னார்வலர் இடத்தில் வந்தார்',
      'sos_active_live_volunteer_on_scene_many_title':
          'தன்னார்வலர்கள் இடத்தில்',
      'sos_active_live_volunteer_on_scene_single_detail':
          'யாரோ உங்களுடன் அல்லது உங்கள் பின்னில் உள்ளனர்.',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} பதிலளிப்பாளர்கள் இடத்தில் குறிக்கப்பட்டுள்ளனர்.',
      'sos_active_live_responder_location_title':
          'நேரலை பதிலளிப்பாளர் இருப்பிடம்',
      'sos_active_live_responder_location_detail':
          'ஒதுக்கப்பட்ட தன்னார்வலர் GPS வரைபடத்தில் புதுப்பிக்கப்படுகிறது.',
      'sos_active_live_professional_dispatch_title':
          'தொழில்முறை அனுப்பீடு செயலில்',
      'sos_active_live_professional_dispatch_detail':
          'ஒருங்கிணைக்கப்பட்ட சேவைகள் இந்த சம்பவத்தில் வேலை செய்கின்றன.',
      'sos_active_ambulance_200m_detail':
          'ஆம்புலன்ஸ் இடத்தில் — சுமார் 200 மீட்டருக்குள்.',
      'sos_active_ambulance_200m_semantic_label':
          'ஆம்புலன்ஸ் சுமார் இருநூறு மீட்டருக்குள் இடத்தில்',
      'sos_active_bridge_channel_on_suffix': ' · {n} சேனலில்',
      'sos_active_bridge_channel_voice': 'அவசர குரல் சேனல்',
      'sos_active_bridge_channel_ptt': 'அவசர சேனல் · Firebase PTT',
      'sos_active_bridge_channel_failed': 'அவசர சேனல் · மறுமுயற்சி செய்க',
      'sos_active_bridge_channel_connecting': 'அவசர சேனல் · இணைக்கிறது',
      'sos_active_dispatch_contact_hospitals_default':
          'உங்கள் இருப்பிடம் மற்றும் அவசர வகை அடிப்படையில் அருகிலுள்ள மருத்துவமனைகளைத் தொடர்புகொள்கிறோம்.',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'ஆம்புலன்ஸ் குழு அறிவிக்கப்பட்டது',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'கூட்டாளி மருத்துவமனை உங்கள் வழக்கை ஏற்றுக்கொண்டது. ஆம்புலன்ஸ் ஆபரேட்டர்கள் அறிவிக்கப்படுகின்றனர்.',
      'sos_active_dispatch_ambulance_confirmed_title':
          'ஆம்புலன்ஸ் உறுதிப்படுத்தப்பட்டது',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'அலகு {unit} உங்களை நோக்கி வருகிறது. பதிலளிப்பாளர்கள் சென்று சேரும் இடத்தில் இருங்கள்.',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'ஒரு ஆம்புலன்ஸ் உங்களை நோக்கி வருகிறது. பதிலளிப்பாளர்கள் சென்று சேரும் இடத்தில் இருங்கள்.',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'ஆம்புலன்ஸ் ஒப்படைப்பு தாமதம்',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'மருத்துவமனை ஏற்றுக்கொண்டது, ஆனால் நேரத்தில் ஆம்புலன்ஸ் குழு உறுதிப்படுத்தவில்லை. அனுப்பீடு உயர்த்தப்படுகிறது — தேவையாயின் 112-ஐ அழைக்கவும்.',
      'sos_active_dispatch_pending_title_trying': 'முயற்சி: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · மருத்துவமனை பதிலுக்காக காத்திருக்கிறது.',
      'sos_active_dispatch_accepted_title':
          '{hospital} ஏற்றுக்கொண்டது',
      'sos_active_dispatch_accepted_subtitle':
          'ஆம்புலன்ஸ் அனுப்பீடு ஒருங்கிணைக்கப்படுகிறது.',
      'sos_active_dispatch_exhausted_title':
          'அனைத்து மருத்துவமனைகளுக்கும் அறிவிப்பு',
      'sos_active_dispatch_exhausted_subtitle':
          'நேரத்தில் எந்த மருத்துவமனையும் ஏற்கவில்லை. அனுப்பீடு அவசர சேவைகளுக்கு உயர்த்தப்படுகிறது.',
      'sos_active_dispatch_generic_title': 'மருத்துவமனை அனுப்பீடு',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'அவசர குரல் சேனல்',
      'volunteer_bridge_join_hint_incident':
          'இணைவது இந்த சம்பவத்தைப் பயன்படுத்துகிறது: உங்கள் எண் பொருந்தினால் அவசர தொடர்பு; இல்லையேல் ஏற்றுக்கொள்ளப்பட்ட தன்னார்வலர்.',
      'volunteer_bridge_join_hint_elite':
          'நீங்கள் ஏற்றுக்கொள்ளப்பட்ட பதிலளிப்பாளராக இருக்கும்போது இணைவு உங்கள் எலைட் அணுகலைப் பயன்படுத்துகிறது; இல்லையேல் உங்கள் எண் பொருந்தினால் தொடர்பு.',
      'volunteer_bridge_join_hint_desk':
          'உங்கள் சுயவிவரத்தில் உள்ள அவசர சேவைகள் டெஸ்க்காக அனுப்பீடாக நீங்கள் இணைகிறீர்கள்.',
      'volunteer_bridge_join_voice_btn': 'குரலில் சேரவும்',
      'volunteer_bridge_connecting_btn': 'இணைக்கிறது…',
      'volunteer_bridge_incident_id_hint': 'சம்பவ ID',
      'volunteer_consignment_live_location_hint':
          'நீங்கள் கன்சைன்மென்ட்டில் இருக்கும்போது, வரைபடம் மற்றும் ETA துல்லியமாக இருக்க உங்கள் நேரலை இருப்பிடம் இந்த சம்பவத்துடன் பகிரப்படுகிறது.',
      'volunteer_consignment_low_power_label': 'குறைந்த சக்தி',
      'volunteer_consignment_normal_gps_label': 'சாதாரண GPS',
      'bridge_card_incident_id_missing': 'சம்பவ ஐடி இல்லை.',
      'bridge_card_ptt_only_snackbar':
          'ஆப்ஸ் கன்சோல் பலியின் குரலை Firebase PTT மூலம் வழியாக்கியது. WebRTC பிரிட்ஜ் இணைப்பு முடக்கப்பட்டுள்ளது.',
      'bridge_card_ptt_only_banner':
          'கன்சோல் குரலை Firebase PTT மூலம் அனுப்பியது — இந்த ஃப்ளீட்டுக்கு LiveKit பிரிட்ஜ் இணைப்பு முடக்கப்பட்டுள்ளது.',
      'bridge_card_connected_snackbar': 'குரல் சேனலுடன் இணைக்கப்பட்டது.',
      'bridge_card_could_not_join': 'இணைய முடியவில்லை: {err}',
      'bridge_card_voice_channel_title': 'குரல் சேனல்',
      'bridge_card_calm_disclaimer':
          'அமைதியாக இருங்கள், தெளிவாக பேசுங்கள். நிலையான தொனி பாதிக்கப்பட்டவர் மற்றும் மற்ற உதவியாளர்களுக்கு உதவுகிறது. கத்தவோ வார்த்தைகளை அவசரப்படவோ வேண்டாம்.',
      'bridge_card_cancel': 'ரத்து',
      'bridge_card_join_voice': 'குரலில் சேரவும்',
      'bridge_card_voice_connected': 'குரல் இணைக்கப்பட்டது',
      'bridge_card_in_channel': 'சேனலில் {n} பேர்',
      'bridge_card_transmitting': 'பரிமாறுகிறது…',
      'bridge_card_hold_to_talk': 'பேச பிடித்துக்கொள்ளுங்கள்',
      'bridge_card_disconnect': 'துண்டிக்க',
      'vol_ems_banner_en_route': 'ஆம்புலன்ஸ் சம்பவ இடத்திற்குச் செல்கிறது',
      'vol_ems_banner_on_scene': 'ஆம்புலன்ஸ் இடத்தில் (~200 மீ)',
      'vol_ems_banner_returning': 'ஆம்புலன்ஸ் மருத்துவமனைக்கு திரும்புகிறது',
      'vol_ems_banner_complete': 'பதில் முடிந்தது · ஆம்புலன்ஸ் நிலையத்தில்',
      'vol_ems_banner_complete_with_cycle':
          'பதில் முடிந்தது · ஆம்புலன்ஸ் நிலையத்தில் · மொத்த சுழற்சி {m}நி {s}வி',
      'vol_tooltip_lifeline_first_aid':
          'லைஃப்லைன் — முதலுதவி வழிகாட்டிகள் (பதிலில் இருக்கும்)',
      'vol_tooltip_exit_mission': 'பணி முடிவு',
      'vol_low_power_tracking_hint':
          'குறைந்த-சக்தி கண்காணிப்பு: உங்கள் நிலையை குறைவாக, பெரிய நகர்வுகளுக்குப் பிறகு மட்டும் ஒத்திசைக்கிறோம். டிஸ்பாட்ச் உங்கள் கடைசி புள்ளியை காண்கிறது.',
      'vol_marker_you': 'நீங்கள்',
      'vol_marker_active_unit': 'செயல்பாட்டு பிரிவு',
      'vol_marker_practice_incident': 'பயிற்சி சம்பவம்',
      'vol_marker_accident_scene': 'விபத்து இடம்',
      'vol_marker_training_pin': 'பயிற்சி பின் — உண்மையான SOS இல்லை',
      'vol_marker_high_severity': 'GITM கல்லூரி - அதிக தீவிரம்',
      'vol_marker_accepted_hospital': 'ஏற்றது: {hospital}',
      'vol_marker_trying_hospital': 'முயற்சி: {hospital}',
      'vol_marker_ambulance_on_scene': 'ஆம்புலன்ஸ் இடத்தில்!',
      'vol_marker_ambulance_en_route': 'ஆம்புலன்ஸ் வரும் வழியில்',
      'vol_badge_at_scene_pin': 'இட பின்னில்',
      'vol_badge_in_5km_zone': '5 கிமீ மண்டலத்தில்',
      'vol_badge_en_route': 'வரும் வழியில்',
    },

    // ── Telugu (తెలుగు) ────────────────────────────────────────────────────
    'te': {
      'app_name': 'EmergencyOS',
      'profile_title': 'ప్రొఫైల్ & వైద్య గుర్తింపు',
      'language': 'భాష',
      'save_medical_profile': 'వైద్య ప్రొఫైల్ సేవ్ చేయండి',
      'critical_medical_info': 'కీలక వైద్య సమాచారం',
      'emergency_contacts': 'అత్యవసర సంప్రదింపులు',
      'golden_hour_details': 'గోల్డెన్ అవర్ వివరాలు',
      'sos_lock': 'SOS లాక్',
      'top_life_savers': 'అగ్ర ప్రాణ రక్షకులు',
      'lives_saved': 'రక్షించిన ప్రాణాలు',
      'active_alerts': 'యాక్టివ్ అలర్ట్‌లు',
      'rank': 'ర్యాంక్',
      'on_duty': 'డ్యూటీలో',
      'standby': 'స్టాండ్‌బై',
      'sos': 'SOS',
      'call_now': 'ఇప్పుడు కాల్ చేయండి',
      'quick_guide': 'త్వరిత గైడ్',
      'detailed_instructions': 'వివరమైన సూచనలు',
      'red_flags': 'ప్రమాద సంకేతాలు',
      'cautions': 'జాగ్రత్తలు',
      'voice_walkthrough': 'వాయిస్ వాక్‌త్రూ',
      'playing': 'ప్లే అవుతోంది...',
      'swipe_next_guide': 'తదుపరి గైడ్ కోసం స్వైప్ చేయండి',
      'watch_video_guide': 'పూర్తి వీడియో గైడ్ చూడండి',
      'emergency_grid_scan': 'అత్యవసర గ్రిడ్ స్కాన్',
      'area_telemetry': 'ప్రాంత టెలిమెట్రీ & ప్రమాద సూచిక',
      'report_hazard': 'ప్రమాదాన్ని నివేదించండి',
      'todays_duty': 'నేటి డ్యూటీ',
      'blood_type': 'రక్త రకం',
      'allergies': 'అలర్జీలు',
      'medical_conditions': 'వైద్య పరిస్థితులు',
      'contact_name': 'ప్రాథమిక సంప్రదింపు పేరు',
      'contact_phone': 'ప్రాథమిక సంప్రదింపు ఫోన్',
      'relationship': 'సంబంధం',
      'medications': 'ప్రస్తుత మందులు',
      'organ_donor': 'అవయవ దాత స్థితి',
      'good_morning': 'శుభోదయం,',
      'good_afternoon': 'శుభ మధ్యాహ్నం,',
      'good_evening': 'శుభ సాయంత్రం,',
      'hospitals': 'ఆసుపత్రులు',
      'visual_walkthrough': 'విజువల్ వాక్‌త్రూ',
      'lifeline': 'లైఫ్‌లైన్',
      'nav_home': 'హోమ్',
      'nav_map': 'మ్యాప్',
      'nav_grid': 'గ్రిడ్',
      'nav_profile': 'ప్రొఫైల్',
      'map_caching_offline_pct': 'ఆఫ్‌లైన్ కోసం ప్రాంతం క్యాష్ — {pct}%',
      'map_drill_practice_banner':
          'ప్రాక్టీస్ గ్రిడ్: పల్సింగ్ పిన్‌లు = డెమో సక్రియ హెచ్చరికలు. పొరల కోసం మ్యాప్ ఫిల్టర్‌లు — నిజమైన డేటా కాదు.',
      'map_recenter_tooltip': 'మళ్లీ కేంద్రీకరించు',
      'map_legend_hospital': 'ఆసుపత్రి',
      'map_legend_live_sos_history': 'లైవ్ SOS / చరిత్ర',
      'map_legend_past_this_hex': 'గత (ఈ హెక్స్)',
      'map_legend_in_area': 'ప్రాంతంలో {n}',
      'map_legend_in_cell': 'సెల్‌లో {n}',
      'map_legend_volunteers_on_duty': 'డ్యూటీలో స్వయంసేవకులు',
      'map_legend_volunteers_in_grid': 'గ్రిడ్‌లో {n}',
      'map_legend_responder_scene': 'ప్రతిస్పందిక → దృశ్యం',
      'map_responder_routes_one': '{n} మార్గం',
      'map_responder_routes_many': '{n} మార్గాలు',
      'map_filters_title': 'మ్యాప్ ఫిల్టర్‌లు',
      'step_prefix': 'దశ',
      'highlights_steps': 'ఒక్కొక్కటిగా దశలను చూపిస్తుంది',
      'offline_mode': 'ఆఫ్‌లైన్ — నెట్‌వర్క్ డిస్‌కనెక్ట్',
      'volunteer': 'వాలంటీర్',
      'unranked': 'ర్యాంక్ లేదు',
      'live': 'లైవ్',
      'you': 'మీరు',
      'saved': 'రక్షించారు',
      'xp_responses': 'XP · {0} ప్రతిస్పందనలు',
      'duty_monitoring': 'మీరు డ్యూటీలో ఉన్నప్పుడు SOS పాప్-అప్‌లు ఆన్ చేయబడ్డాయి.',
      'turn_on_duty_msg': 'SOS పాప్-అప్‌లు అందుకోవడానికి డ్యూటీ ఆన్ చేయండి.',
      'on_duty_snack': 'డ్యూటీలో — మీ ప్రాంతంలో సంఘటనలను పర్యవేక్షిస్తోంది...',
      'off_duty_snack': 'స్టాండ్‌బై — డ్యూటీ సెషన్ రికార్డ్ చేయబడింది.',
      'leaderboard_offline': 'లీడర్‌బోర్డ్ ఆఫ్‌లైన్',
      'leaderboard_offline_sub': 'సింక్ ఆగింది. కాష్ స్కోర్‌లు చూపబడ్డాయి.',
      'set_sos_pin_first': 'ముందు SOS పిన్ సెట్ చేయండి',
      'set_pin_safety_msg': 'భద్రత కోసం, SOS సృష్టించే ముందు పిన్ సెట్ చేయాలి.',
      'set_pin_now': 'ఇప్పుడు పిన్ సెట్ చేయండి',
      'later': 'తర్వాత',
      'sos_are_you_conscious':
          'మీరు అవగాహనలో ఉన్నారా? దయచేసి అవును లేదా కాదు అని సమాధానం ఇవ్వండి.',
      'sos_tts_opening_guidance':
          'మీ SOS సక్రియంగా ఉంది. సహాయం మార్గంలో ఉంది. మాటల సూచనలను అనుసరించి స్పందించడానికి టాప్ చేయండి.',
      'sos_interview_q1_prompt': 'ఏమి జరుగుతోంది? (అత్యవసర రకం)',
      'sos_interview_q2_prompt': 'మీరు సురక్షితంగా ఉన్నారా? ఎంత తీవ్రం?',
      'sos_interview_q3_prompt': 'ఎంత మంది పాల్గొన్నారు?',
      'sos_chip_cat_accident': 'ప్రమాదం',
      'sos_chip_cat_medical': 'వైద్యం',
      'sos_chip_cat_hazard': 'అపాయం (నిప్పు, మునిగిపోవడం మొదలైనవి)',
      'sos_chip_cat_assault': 'దాడి',
      'sos_chip_cat_other': 'ఇతర',
      'sos_chip_safe_critical': 'తీవ్ర (ప్రాణాంతకం)',
      'sos_chip_safe_injured': 'గాయపడింది కానీ స్థిరం',
      'sos_chip_safe_danger': 'గాయం లేదు కానీ ప్రమాదంలో',
      'sos_chip_safe_safe_now': 'ఇప్పుడు సురక్షితం',
      'sos_chip_people_me': 'నేను మాత్రమే',
      'sos_chip_people_two': 'ఇద్దరు',
      'sos_chip_people_many': 'ఇద్దరికంటే ఎక్కువ',
      'sos_tts_interview_saved':
          'బాధిత ఇంటర్వ్యూ డేటా అంతా సేవ్ చేయబడింది. రెస్పాండర్లకు వివరాలు ఉన్నాయి. ప్రతి 60 సెకన్లకు అవగాహన తనిఖీ కొనసాగుతుంది.',
      'sos_tts_map_routes':
          'మ్యాప్ ట్యాబ్ తెరవండి: ఎరుపు కేటాయించిన ఆసుపత్రికి రోడ్ మార్గం లేదా సమీప మార్గం; ఆకుపచ్చ వాలంటీర్ మార్గం. అత్యవసర వాయిస్ ఛానెల్‌లో ఉండండి.',
      'sos_tts_emergency_contacts_on_file':
          'Your emergency contact from your profile is attached to this SOS. SMS updates may be sent when that option is enabled.',
      'sos_tts_conscious_no_answer_attempt':
          'సమాధానం లేదు. అవగాహన తనిఖీ {max}లో {n}. ఒక నిమిషంలో మళ్లీ అడుగుతాము.',
      'voice_volunteer_accepted':
          'స్వయంసేవకుడు అంగీకరించారు. సహాయం మార్గంలో ఉంది.',
      'voice_ambulance_dispatched_eta':
          'అంబులెన్స్ పంపబడింది. అంచనా వచ్చే సమయం: {eta}.',
      'voice_police_dispatched_eta':
          'పోలీసులు పంపబడ్డారు. అంచనా వచ్చే సమయం: {eta}.',
      'voice_ambulance_on_scene_victim':
          'అంబులెన్స్ స్థలంలో ఉంది — మీకు సుమారు రెండు వందల మీటర్ల దూరంలో.',
      'voice_ambulance_on_scene_volunteer':
          'అంబులెన్స్ స్థలంలో ఉంది — సంఘటనకు సుమారు రెండు వందల మీటర్లలోపు.',
      'voice_ambulance_returning': 'అంబులెన్స్ ఆసుపత్రికి తిరిగి వెళ్తోంది.',
      'voice_response_complete_station':
          'ప్రతిస్పందన పూర్తి. అంబులెన్స్ స్టేషన్ వద్ద.',
      'voice_response_complete_cycle':
          'ప్రతిస్పందన పూర్తి. అంబులెన్స్ స్టేషన్ వద్ద. మొత్తం చక్రం {minutes} నిమిషాలు {seconds} సెకనులు.',
      'voice_volunteers_on_scene_count':
          '{n} స్వయంసేవకులు ఇప్పుడు స్థలంలో ఉన్నారు.',
      'voice_one_volunteer_on_scene': 'ఒక స్వయంసేవకుడు స్థలంలో ఉన్నాడు.',
      'voice_ptt_joined_comms': '{who} వాయిస్ కమ్యూనికేషన్‌లో చేరారు.',
      'voice_tts_unavailable_banner':
          'వాయిస్ మార్గదర్శకత్వం అందుబాటులో లేదు — స్క్రీన్‌పై ఉన్న వచనాన్ని చదవండి.',
      'language_picker_title': 'భాష',
      'volunteer_victim_medical_card': 'బాధిత వైద్య కార్డ్',
      'volunteer_dispatch_milestone_title': 'డిస్పాచ్ నవీకరణలు',
      'volunteer_dispatch_milestone_hospital': 'ఆసుపత్రి అంగీకరించింది: {hospital}',
      'volunteer_dispatch_milestone_unit': 'అంబులెన్స్ యూనిట్: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'అంబులెన్స్ క్రూ: సమన్వయం…',
      'volunteer_dispatch_milestone_en_route': 'అంబులెన్స్ మార్గంలో',
      'volunteer_triage_qr_report_title': 'QR లేదా నొక్కండి నివేదిక',
      'volunteer_triage_qr_report_subtitle':
          'హ్యాండ్‌ఆఫ్ కోసం కోడ్ స్కాన్ చేయండి లేదా నివేదికను సేవ్ చేయడానికి నొక్కండి.',
      'volunteer_triage_show_qr': 'QR చూపు',
      'volunteer_triage_tap_report': 'నివేదిక',
      'volunteer_triage_qr_title': 'ఘటన హ్యాండ్‌ఆఫ్ QR',
      'volunteer_triage_qr_body': 'జోడించిన సిబ్బంది లేదా EMSతో పంచుకోండి.',
      'volunteer_triage_report_saved': 'నివేదిక ఈ ఘటన కింద సేవ్ చేయబడింది.',
      'volunteer_triage_report_failed': 'నివేదికను సేవ్ చేయలేకపోయాము: ',
      'volunteer_victim_medical_offline_hint':
          'SOS ప్యాకెట్ నుండి — ఆఫ్‌లైన్‌లో పరికర కాష్ నుండి అందుబాటులో.',
      'volunteer_victim_consciousness_title': 'అవగాహన',
      'volunteer_victim_three_questions': 'ప్రారంభ బాధిత సమాధానాలు',
      'volunteer_major_updates_log': 'ప్రధాన అప్‌డేట్‌లు మాత్రమే',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'టియర్ {tier} వరకు పెంచుతున్నాము. ఆసుపత్రి {hospital} ప్రయత్నిస్తున్నాము.',
      'volunteer_dispatch_trying_hospital': 'ఆసుపత్రి {hospital} ప్రయత్నిస్తున్నాము.',
      'volunteer_dispatch_hospital_accepted':
          '{hospital} అత్యవసరాన్ని అంగీకరించింది. అంబులెన్స్ సమన్వయం ప్రగతిలో ఉంది.',
      'volunteer_dispatch_all_hospitals_notified':
          'అన్ని ఆసుపత్రులకు తెలియజేశాము. అత్యవసర సేవలకు పైకి పంపుతున్నాము.',
      'sos_dispatch_alerting_nearest_trying':
          'మీ ప్రాంతంలో సమీప ఆసుపత్రిని అలర్ట్ చేస్తున్నాము. {hospital} ప్రయత్నిస్తున్నాము.',
      'sos_dispatch_escalating_tier_trying':
          'ప్రతిస్పందన లేదు. టియర్ {tier} వరకు పెంచుతున్నాము. {hospital} ప్రయత్నిస్తున్నాము.',
      'sos_dispatch_retry_previous_trying':
          'మునపటి ఆసుపత్రి నుండి ప్రతిస్పందన లేదు. {hospital} ప్రయత్నిస్తున్నాము.',
      'sos_dispatch_all_hospitals_call_112':
          'అన్ని ఆసుపత్రులకు తెలియజేశాము. అత్యవసర సేవలకు దయచేసి 112 కు కాల్ చేయండి.',
      'sos_active_title_big': 'సక్రియ SOS',
      'sos_active_help_coming': 'సహాయం వస్తోంది. ప్రశాంతంగా ఉండండి.',
      'sos_active_badge_waiting': 'వేచి ఉండు',
      'sos_active_badge_en_route_count': '{n} దారిలో',
      'sos_active_mini_ambulance': 'అంబులెన్స్',
      'sos_active_mini_on_scene': 'స్థలంలో',
      'sos_active_mini_status': 'స్థితి',
      'sos_active_volunteers_count_short': '{n} స్వచ్ఛందసేవకులు',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title':
          'అన్ని ఆసుపత్రులకు తెలియజేశాము',
      'sos_active_all_hospitals_notified_subtitle':
          'సకాలంలో ఏ ఆసుపత్రి స్వీకరించలేదు. డిస్పాచ్ అత్యవసర సేవలకు ఎస్కలేట్ చేస్తోంది.',
      'sos_active_position_refresh_note':
          'బ్యాటరీని ఆదా చేయడానికి SOS సమయంలో మీ స్థానం సుమారు 45 సెకన్లకు ఒకసారి నవీకరించబడుతుంది. యాప్ తెరిచి ఉంచండి మరియు వీలైతే ఛార్జ్‌కి కనెక్ట్ చేయండి.',
      'sos_active_mic_active': 'మైక్ · క్రియాశీలం',
      'sos_active_mic_active_detail':
          'లైవ్ ఛానెల్ మీ మైక్రోఫోన్‌ను స్వీకరిస్తోంది.',
      'sos_active_mic_standby': 'మైక్ · స్టాండ్‌బై',
      'sos_active_mic_standby_detail': 'వాయిస్ ఛానెల్ కోసం వేచి ఉంది…',
      'sos_active_mic_connecting': 'మైక్ · కనెక్ట్ అవుతోంది',
      'sos_active_mic_connecting_detail':
          'అత్యవసర వాయిస్ ఛానెల్‌లో చేరుతోంది…',
      'sos_active_mic_reconnecting': 'మైక్ · తిరిగి కనెక్ట్',
      'sos_active_mic_reconnecting_detail': 'లైవ్ ఆడియోను పునరుద్ధరిస్తోంది…',
      'sos_active_mic_failed': 'మైక్ · అంతరాయం',
      'sos_active_mic_failed_detail':
          'వాయిస్ ఛానెల్ అందుబాటులో లేదు. పైన RETRY వినియోగించండి.',
      'sos_active_mic_ptt_only': 'మైక్ · సంఘటన ఛానెల్',
      'sos_active_mic_ptt_only_detail':
          'ఆపరేషన్స్ కన్సోల్ Firebase PTT ద్వారా వాయిస్‌ని రూట్ చేసింది. స్పందించేవారిని చేరడానికి బ్రాడ్‌కాస్ట్‌ను పట్టుకోండి.',
      'sos_active_mic_interrupted': 'మైక్ · విరామం',
      'sos_active_mic_interrupted_detail':
          'యాప్ ఆడియో ప్రాసెస్ చేస్తున్నప్పుడు చిన్న విరామం.',
      'sos_active_consciousness_note':
          'స్పృహ తనిఖీలకు అవును లేదా కాదు అని సమాధానం ఇవ్వండి; ఇతర ప్రాంప్ట్‌లు స్క్రీన్ ఎంపికలను వినియోగిస్తాయి.',
      'sos_active_live_updates_header': 'లైవ్ నవీకరణలు',
      'sos_active_live_updates_subtitle':
          'డిస్పాచ్, స్వచ్ఛందసేవకులు & పరికరం',
      'sos_active_live_tag': 'లైవ్',
      'sos_active_activity_log': 'కార్యకలాప లాగ్',
      'sos_active_header_stat_coordinating_crew': 'సిబ్బంది సమన్వయం',
      'sos_active_header_stat_coordinating': 'సమన్వయం',
      'sos_active_header_stat_en_route': 'మార్గంలో',
      'sos_active_header_stat_route_min': '~{n} నిమి',
      'sos_active_live_sos_is_live_title': 'SOS లైవ్‌లో ఉంది',
      'sos_active_live_sos_is_live_detail':
          'మీ స్థానం మరియు వైద్య ఫ్లాగ్‌లు అత్యవసర నెట్‌వర్క్‌లో ఉన్నాయి.',
      'sos_active_live_volunteers_notified_title':
          'స్వచ్ఛందసేవకులకు తెలియజేశారు',
      'sos_active_live_volunteers_notified_detail':
          'సమీపంలోని స్వచ్ఛందసేవకులు ఈ సంఘటనను నిజ సమయంలో స్వీకరిస్తారు.',
      'sos_active_live_bridge_connected_title':
          'అత్యవసర వాయిస్ బ్రిడ్జ్ కనెక్ట్ అయ్యింది',
      'sos_active_live_bridge_connected_detail':
          'డిస్పాచ్ డెస్క్ మరియు స్పందించేవారు ఈ ఛానెల్‌ను వినగలరు.',
      'sos_active_live_ptt_title': 'Firebase PTT ద్వారా వాయిస్',
      'sos_active_live_ptt_detail':
          'ఈ ఫ్లీట్‌కు లైవ్ WebRTC బ్రిడ్జ్ ఆఫ్‌లో ఉంది. వాయిస్ మరియు టెక్స్ట్ నవీకరణల కోసం బ్రాడ్‌కాస్ట్ ఉపయోగించండి.',
      'sos_active_live_contacts_notified_title':
          'అత్యవసర పరిచయాలకు తెలియజేశారు',
      'sos_active_live_hospital_accepted_title': 'ఆసుపత్రి స్వీకరించింది',
      'sos_active_live_ambulance_unit_assigned_title':
          'అంబులెన్స్ యూనిట్ కేటాయింపు',
      'sos_active_live_ambulance_unit_assigned_subtitle': 'యూనిట్ {unit}',
      'sos_active_live_ambulance_en_route_title': 'అంబులెన్స్ దారిలో',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'దారిలో',
      'sos_active_live_ambulance_en_route_route_eta':
          '~{n} నిమి (మార్గం)',
      'sos_active_live_ambulance_coordination_title': 'అంబులెన్స్ సమన్వయం',
      'sos_active_live_ambulance_coordination_pending':
          'ఆసుపత్రి స్వీకరించింది — అంబులెన్స్ ఆపరేటర్లకు తెలియజేస్తోంది.',
      'sos_active_live_ambulance_coordination_arranging':
          'అంబులెన్స్ సిబ్బంది ఏర్పాట్లు — యూనిట్ దారిలో ఉన్నప్పుడు నిమిషాల ETA.',
      'sos_active_live_responder_status_title': 'స్పందికర్త స్థితి',
      'sos_active_live_volunteer_accepted_single_title':
          'స్వచ్ఛందసేవకుడు స్వీకరించారు',
      'sos_active_live_volunteer_accepted_many_title':
          'స్వచ్ఛందసేవకులు స్వీకరించారు',
      'sos_active_live_volunteer_accepted_single_detail':
          'ఒక స్పందికర్త కేటాయించబడింది మరియు మీకు సహాయం చేయడానికి వస్తున్నారు.',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} స్పందికర్తలు ఈ SOS కు కేటాయించబడ్డారు.',
      'sos_active_live_volunteer_on_scene_single_title':
          'స్వచ్ఛందసేవకుడు స్థలంలోకి చేరుకున్నారు',
      'sos_active_live_volunteer_on_scene_many_title':
          'స్వచ్ఛందసేవకులు స్థలంలో',
      'sos_active_live_volunteer_on_scene_single_detail':
          'ఎవరో మీతో లేదా మీ పిన్ వద్ద ఉన్నారు.',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} స్పందికర్తలు స్థలంలో గుర్తించబడ్డారు.',
      'sos_active_live_responder_location_title':
          'లైవ్ స్పందికర్త స్థానం',
      'sos_active_live_responder_location_detail':
          'కేటాయించబడిన స్వచ్ఛందసేవకుడి GPS మ్యాప్‌లో నవీకరిస్తోంది.',
      'sos_active_live_professional_dispatch_title':
          'ప్రొఫెషనల్ డిస్పాచ్ క్రియాశీలం',
      'sos_active_live_professional_dispatch_detail':
          'సమన్వయ సేవలు ఈ సంఘటనపై పని చేస్తున్నాయి.',
      'sos_active_ambulance_200m_detail':
          'అంబులెన్స్ స్థలంలో — సుమారు 200 మీటర్ల పరిధిలో.',
      'sos_active_ambulance_200m_semantic_label':
          'అంబులెన్స్ సుమారు రెండు వందల మీటర్ల పరిధిలో స్థలంలో',
      'sos_active_bridge_channel_on_suffix': ' · {n} ఛానెల్‌లో',
      'sos_active_bridge_channel_voice': 'అత్యవసర వాయిస్ ఛానెల్',
      'sos_active_bridge_channel_ptt': 'అత్యవసర ఛానెల్ · Firebase PTT',
      'sos_active_bridge_channel_failed':
          'అత్యవసర ఛానెల్ · మళ్లీ ప్రయత్నించండి',
      'sos_active_bridge_channel_connecting':
          'అత్యవసర ఛానెల్ · కనెక్ట్ అవుతోంది',
      'sos_active_dispatch_contact_hospitals_default':
          'మీ స్థానం మరియు అత్యవసర రకం ఆధారంగా సమీప ఆసుపత్రులను సంప్రదిస్తున్నాము.',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'అంబులెన్స్ సిబ్బందికి తెలియజేశారు',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'భాగస్వామ్య ఆసుపత్రి మీ కేసును స్వీకరించింది. అంబులెన్స్ ఆపరేటర్లకు తెలియజేస్తున్నారు.',
      'sos_active_dispatch_ambulance_confirmed_title':
          'అంబులెన్స్ ధృవీకరించబడింది',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'యూనిట్ {unit} మీ వైపు వస్తోంది. స్పందికర్తలు చేరుకోగల చోట ఉండండి.',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'ఒక అంబులెన్స్ మీ వైపు వస్తోంది. స్పందికర్తలు చేరుకోగల చోట ఉండండి.',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'అంబులెన్స్ హ్యాండ్‌ఆఫ్ ఆలస్యం',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'ఆసుపత్రి స్వీకరించింది, కానీ సకాలంలో అంబులెన్స్ సిబ్బంది ధృవీకరించలేదు. డిస్పాచ్ ఎస్కలేట్ చేస్తోంది — అవసరమైతే 112కు కాల్ చేయండి.',
      'sos_active_dispatch_pending_title_trying': 'ప్రయత్నం: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · ఆసుపత్రి ప్రతిస్పందన కోసం వేచి ఉంది.',
      'sos_active_dispatch_accepted_title': '{hospital} స్వీకరించింది',
      'sos_active_dispatch_accepted_subtitle':
          'అంబులెన్స్ డిస్పాచ్ సమన్వయం చేయబడుతోంది.',
      'sos_active_dispatch_exhausted_title':
          'అన్ని ఆసుపత్రులకు తెలియజేశారు',
      'sos_active_dispatch_exhausted_subtitle':
          'సకాలంలో ఏ ఆసుపత్రి స్వీకరించలేదు. డిస్పాచ్ అత్యవసర సేవలకు ఎస్కలేట్ చేస్తోంది.',
      'sos_active_dispatch_generic_title': 'ఆసుపత్రి డిస్పాచ్',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'అత్యవసర వాయిస్ ఛానెల్',
      'volunteer_bridge_join_hint_incident':
          'జాయిన్ ఈ సంఘటనను ఉపయోగిస్తుంది: మీ నంబర్ సరిపోతే అత్యవసర పరిచయం; లేకుంటే ఆమోదించబడిన స్వచ్ఛందసేవకుడు.',
      'volunteer_bridge_join_hint_elite':
          'మీరు ఆమోదించబడిన స్పందికర్త అయినప్పుడు జాయిన్ మీ ఎలైట్ స్వచ్ఛందసేవకుడి యాక్సెస్‌ను ఉపయోగిస్తుంది; లేకుంటే మీ నంబర్ సరిపోతే పరిచయం.',
      'volunteer_bridge_join_hint_desk':
          'మీ ప్రొఫైల్‌లోని అత్యవసర సేవల డెస్క్‌గా మీరు డిస్పాచ్‌గా జాయిన్ అవుతారు.',
      'volunteer_bridge_join_voice_btn': 'వాయిస్‌లో చేరండి',
      'volunteer_bridge_connecting_btn': 'కనెక్ట్ అవుతోంది…',
      'volunteer_bridge_incident_id_hint': 'సంఘటన ID',
      'volunteer_consignment_live_location_hint':
          'మీరు కన్సైన్మెంట్‌లో ఉన్నప్పుడు, మ్యాప్ మరియు ETA ఖచ్చితంగా ఉండటానికి మీ లైవ్ స్థానం ఈ సంఘటనతో భాగస్వామ్యం అవుతుంది.',
      'volunteer_consignment_low_power_label': 'తక్కువ పవర్',
      'volunteer_consignment_normal_gps_label': 'సాధారణ GPS',
      'bridge_card_incident_id_missing': 'సంఘటన ID లేదు.',
      'bridge_card_ptt_only_snackbar':
          'ఆపరేషన్ కన్సోల్ బాధితుడి గొంతును Firebase PTT ద్వారా పంపింది. WebRTC బ్రిడ్జ్ చేరికను నిలిపివేసింది.',
      'bridge_card_ptt_only_banner':
          'కన్సోల్ Firebase PTT ద్వారా వాయిస్ పంపింది — ఈ ఫ్లీట్ కోసం LiveKit బ్రిడ్జ్ నిలిపివేయబడింది.',
      'bridge_card_connected_snackbar': 'వాయిస్ చానెల్‌కు కనెక్ట్ అయ్యారు.',
      'bridge_card_could_not_join': 'చేరలేకపోయాం: {err}',
      'bridge_card_voice_channel_title': 'వాయిస్ చానెల్',
      'bridge_card_calm_disclaimer':
          'ప్రశాంతంగా ఉండండి, స్పష్టంగా మాట్లాడండి. స్థిరమైన స్వరం బాధితుడికి మరియు ఇతర సహాయకులకు సాయపడుతుంది. అరవకండి, తొందరపడి మాట్లాడకండి.',
      'bridge_card_cancel': 'రద్దు',
      'bridge_card_join_voice': 'వాయిస్‌లో చేరండి',
      'bridge_card_voice_connected': 'వాయిస్ కనెక్ట్ అయింది',
      'bridge_card_in_channel': 'చానెల్‌లో {n} మంది',
      'bridge_card_transmitting': 'ప్రసారమవుతోంది…',
      'bridge_card_hold_to_talk': 'మాట్లాడటానికి నొక్కండి',
      'bridge_card_disconnect': 'డిస్‌కనెక్ట్',
      'vol_ems_banner_en_route': 'అంబులెన్స్ సంఘటన స్థలానికి మార్గంలో',
      'vol_ems_banner_on_scene': 'అంబులెన్స్ స్థలంలో (~200 మీ)',
      'vol_ems_banner_returning': 'అంబులెన్స్ ఆసుపత్రికి తిరిగి వెళ్తోంది',
      'vol_ems_banner_complete': 'ప్రతిస్పందన పూర్తయింది · అంబులెన్స్ స్టేషన్‌లో',
      'vol_ems_banner_complete_with_cycle':
          'ప్రతిస్పందన పూర్తయింది · అంబులెన్స్ స్టేషన్‌లో · మొత్తం చక్రం {m}ని {s}సె',
      'vol_tooltip_lifeline_first_aid':
          'లైఫ్‌లైన్ — ప్రథమ చికిత్స గైడ్‌లు (ప్రతిస్పందనలో ఉంటుంది)',
      'vol_tooltip_exit_mission': 'మిషన్ నిష్క్రమణ',
      'vol_low_power_tracking_hint':
          'తక్కువ-పవర్ ట్రాకింగ్: మీ స్థానాన్ని తక్కువ సార్లు, పెద్ద కదలికల తర్వాత మాత్రమే సింక్ చేస్తాము. డిస్పాచ్ మీ చివరి పాయింట్‌ను చూస్తుంది.',
      'vol_marker_you': 'మీరు',
      'vol_marker_active_unit': 'యాక్టివ్ యూనిట్',
      'vol_marker_practice_incident': 'అభ్యాస సంఘటన',
      'vol_marker_accident_scene': 'ప్రమాద స్థలం',
      'vol_marker_training_pin': 'శిక్షణ పిన్ — నిజమైన SOS కాదు',
      'vol_marker_high_severity': 'GITM కళాశాల - అధిక తీవ్రత',
      'vol_marker_accepted_hospital': 'ఆమోదం: {hospital}',
      'vol_marker_trying_hospital': 'ప్రయత్నం: {hospital}',
      'vol_marker_ambulance_on_scene': 'అంబులెన్స్ స్థలంలో!',
      'vol_marker_ambulance_en_route': 'అంబులెన్స్ మార్గంలో',
      'vol_badge_at_scene_pin': 'స్థల పిన్‌లో',
      'vol_badge_in_5km_zone': '5 కిమీ జోన్‌లో',
      'vol_badge_en_route': 'మార్గంలో',
    },

    // ── Kannada (ಕನ್ನಡ) ────────────────────────────────────────────────────
    'kn': {
      'app_name': 'EmergencyOS',
      'profile_title': 'ಪ್ರೊಫೈಲ್ & ವೈದ್ಯಕೀಯ ಗುರುತು',
      'language': 'ಭಾಷೆ',
      'save_medical_profile': 'ವೈದ್ಯಕೀಯ ಪ್ರೊಫೈಲ್ ಉಳಿಸಿ',
      'critical_medical_info': 'ನಿರ್ಣಾಯಕ ವೈದ್ಯಕೀಯ ಮಾಹಿತಿ',
      'emergency_contacts': 'ತುರ್ತು ಸಂಪರ್ಕಗಳು',
      'golden_hour_details': 'ಗೋಲ್ಡನ್ ಅವರ್ ವಿವರಗಳು',
      'sos_lock': 'SOS ಲಾಕ್',
      'top_life_savers': 'ಅಗ್ರ ಜೀವ ರಕ್ಷಕರು',
      'lives_saved': 'ಉಳಿಸಿದ ಜೀವಗಳು',
      'active_alerts': 'ಸಕ್ರಿಯ ಎಚ್ಚರಿಕೆಗಳು',
      'rank': 'ಶ್ರೇಣಿ',
      'on_duty': 'ಕರ್ತವ್ಯದಲ್ಲಿ',
      'standby': 'ಸ್ಟ್ಯಾಂಡ್‌ಬೈ',
      'sos': 'SOS',
      'call_now': 'ಈಗ ಕರೆ ಮಾಡಿ',
      'quick_guide': 'ತ್ವರಿತ ಮಾರ್ಗದರ್ಶಿ',
      'detailed_instructions': 'ವಿವರವಾದ ಸೂಚನೆಗಳು',
      'red_flags': 'ಅಪಾಯ ಸಂಕೇತಗಳು',
      'cautions': 'ಎಚ್ಚರಿಕೆಗಳು',
      'voice_walkthrough': 'ಧ್ವನಿ ಮಾರ್ಗದರ್ಶನ',
      'playing': 'ನುಡಿಸುತ್ತಿದೆ...',
      'swipe_next_guide': 'ಮುಂದಿನ ಮಾರ್ಗದರ್ಶಿಗಾಗಿ ಸ್ವೈಪ್ ಮಾಡಿ',
      'watch_video_guide': 'ಪೂರ್ಣ ವೀಡಿಯೊ ಮಾರ್ಗದರ್ಶಿ ನೋಡಿ',
      'emergency_grid_scan': 'ತುರ್ತು ಗ್ರಿಡ್ ಸ್ಕ್ಯಾನ್',
      'area_telemetry': 'ಪ್ರದೇಶ ಟೆಲಿಮೆಟ್ರಿ & ಅಪಾಯ ಸೂಚಿ',
      'report_hazard': 'ಅಪಾಯ ವರದಿ ಮಾಡಿ',
      'todays_duty': 'ಇಂದಿನ ಕರ್ತವ್ಯ',
      'blood_type': 'ರಕ್ತದ ಗುಂಪು',
      'allergies': 'ಅಲರ್ಜಿಗಳು',
      'medical_conditions': 'ವೈದ್ಯಕೀಯ ಸ್ಥಿತಿಗಳು',
      'contact_name': 'ಪ್ರಾಥಮಿಕ ಸಂಪರ್ಕ ಹೆಸರು',
      'contact_phone': 'ಪ್ರಾಥಮಿಕ ಸಂಪರ್ಕ ಫೋನ್',
      'relationship': 'ಸಂಬಂಧ',
      'medications': 'ಪ್ರಸ್ತುತ ಔಷಧಗಳು',
      'organ_donor': 'ಅಂಗ ದಾನಿ ಸ್ಥಿತಿ',
      'good_morning': 'ಶುಭೋದಯ,',
      'good_afternoon': 'ಶುಭ ಮಧ್ಯಾಹ್ನ,',
      'good_evening': 'ಶುಭ ಸಂಜೆ,',
      'hospitals': 'ಆಸ್ಪತ್ರೆಗಳು',
      'visual_walkthrough': 'ದೃಶ್ಯ ಮಾರ್ಗದರ್ಶನ',
      'lifeline': 'ಲೈಫ್‌ಲೈನ್',
      'nav_home': 'ಹೋಮ್',
      'nav_map': 'ನಕ್ಷೆ',
      'nav_grid': 'ಗ್ರಿಡ್',
      'nav_profile': 'ಪ್ರೊಫೈಲ್',
      'map_caching_offline_pct': 'ಆಫ್‌ಲೈನ್‌ಗಾಗಿ ಪ್ರದೇಶ ಕ್ಯಾಶ್ — {pct}%',
      'map_drill_practice_banner':
          'ಅಭ್ಯಾಸ ಗ್ರಿಡ್: ಪಲ್ಸಿಂಗ್ ಪಿನ್‌ಗಳು = ಡೆಮೋ ಸಕ್ರಿಯ ಎಚ್ಚರಿಕೆಗಳು. ಪದರಗಳಿಗೆ ನಕ್ಷೆ ಫಿಲ್ಟರ್‌ಗಳು — ನಿಜವಾದ ಡೇಟಾ ಅಲ್ಲ.',
      'map_recenter_tooltip': 'ಮತ್ತೆ ಕೇಂದ್ರೀಕರಿಸಿ',
      'map_legend_hospital': 'ಆಸ್ಪತ್ರೆ',
      'map_legend_live_sos_history': 'ಲೈವ್ SOS / ಇತಿಹಾಸ',
      'map_legend_past_this_hex': 'ಹಿಂದಿನ (ಈ ಹೆಕ್ಸ್)',
      'map_legend_in_area': 'ಪ್ರದೇಶದಲ್ಲಿ {n}',
      'map_legend_in_cell': 'ಸೆಲ್‌ನಲ್ಲಿ {n}',
      'map_legend_volunteers_on_duty': 'ಕರ್ತವ್ಯದಲ್ಲಿ ಸ್ವಯಂಸೇವಕರು',
      'map_legend_volunteers_in_grid': 'ಗ್ರಿಡ್‌ನಲ್ಲಿ {n}',
      'map_legend_responder_scene': 'ಪ್ರತಿಕ್ರಿಯೆ → ದೃಶ್ಯ',
      'map_responder_routes_one': '{n} ಮಾರ್ಗ',
      'map_responder_routes_many': '{n} ಮಾರ್ಗಗಳು',
      'map_filters_title': 'ನಕ್ಷೆ ಫಿಲ್ಟರ್‌ಗಳು',
      'step_prefix': 'ಹಂತ',
      'highlights_steps': 'ಒಂದೊಂದಾಗಿ ಹಂತಗಳನ್ನು ತೋರಿಸುತ್ತದೆ',
      'offline_mode': 'ಆಫ್‌ಲೈನ್ — ನೆಟ್‌ವರ್ಕ್ ಸಂಪರ್ಕ ಕಡಿತ',
      'volunteer': 'ಸ್ವಯಂಸೇವಕ',
      'unranked': 'ಶ್ರೇಣಿ ಇಲ್ಲ',
      'live': 'ಲೈವ್',
      'you': 'ನೀವು',
      'saved': 'ಉಳಿಸಿದ',
      'xp_responses': 'XP · {0} ಪ್ರತಿಕ್ರಿಯೆಗಳು',
      'duty_monitoring': 'ನೀವು ಕರ್ತವ್ಯದಲ್ಲಿರುವಾಗ SOS ಪಾಪ್-ಅಪ್‌ಗಳು ಆನ್ ಆಗಿವೆ.',
      'turn_on_duty_msg': 'SOS ಪಾಪ್-ಅಪ್‌ಗಳನ್ನು ಪಡೆಯಲು ಕರ್ತವ್ಯ ಆನ್ ಮಾಡಿ.',
      'on_duty_snack': 'ಕರ್ತವ್ಯದಲ್ಲಿ — ನಿಮ್ಮ ಪ್ರದೇಶದಲ್ಲಿ ಘಟನೆಗಳನ್ನು ಮೇಲ್ವಿಚಾರಣೆ ಮಾಡಲಾಗುತ್ತಿದೆ...',
      'off_duty_snack': 'ಸ್ಟ್ಯಾಂಡ್‌ಬೈ — ಕರ್ತವ್ಯ ಅವಧಿ ದಾಖಲಾಗಿದೆ.',
      'leaderboard_offline': 'ಲೀಡರ್‌ಬೋರ್ಡ್ ಆಫ್‌ಲೈನ್',
      'leaderboard_offline_sub': 'ಸಿಂಕ್ ನಿಲ್ಲಿಸಲಾಗಿದೆ. ಕ್ಯಾಶ್ ಸ್ಕೋರ್‌ಗಳು.',
      'set_sos_pin_first': 'ಮೊದಲು SOS ಪಿನ್ ಸೆಟ್ ಮಾಡಿ',
      'set_pin_safety_msg': 'ಸುರಕ್ಷತೆಗಾಗಿ, SOS ರಚಿಸುವ ಮೊದಲು ಪಿನ್ ಸೆಟ್ ಮಾಡಬೇಕು.',
      'set_pin_now': 'ಈಗ ಪಿನ್ ಸೆಟ್ ಮಾಡಿ',
      'later': 'ನಂತರ',
      'sos_are_you_conscious':
          'ನೀವು ಪ್ರಜ್ಞೆಯಲ್ಲಿದ್ದೀರಾ? ದಯವಿಟ್ಟು ಹೌದು ಅಥವಾ ಇಲ್ಲ ಎಂದು ಉತ್ತರಿಸಿ.',
      'sos_tts_opening_guidance':
          'ನಿಮ್ಮ SOS ಸಕ್ರಿಯವಾಗಿದೆ. ಸಹಾಯ ಬರುತ್ತಿದೆ. ಮಾತಿನ ಸೂಚನೆಗಳನ್ನು ಅನುಸರಿಸಿ ಮತ್ತು ಉತ್ತರಿಸಲು ಟ್ಯಾಪ್ ಮಾಡಿ.',
      'sos_interview_q1_prompt': 'ಏನಾಗುತ್ತಿದೆ? (ತುರ್ತು ಪ್ರಕಾರ)',
      'sos_interview_q2_prompt': 'ನೀವು ಸುರಕ್ಷಿತರೇ? ಎಷ್ಟು ಗಂಭೀರ?',
      'sos_interview_q3_prompt': 'ಎಷ್ಟು ಜನರು ಒಳಗೊಂಡಿದ್ದಾರೆ?',
      'sos_chip_cat_accident': 'ಅಪಘಾತ',
      'sos_chip_cat_medical': 'ವೈದ್ಯಕೀಯ',
      'sos_chip_cat_hazard': 'ಅಪಾಯ (ಬೆಂಕಿ, ಮುಳುಗುವಿಕೆ ಇತ್ಯಾದಿ)',
      'sos_chip_cat_assault': 'ದಾಳಿ',
      'sos_chip_cat_other': 'ಇತರ',
      'sos_chip_safe_critical': 'ಗಂಭೀರ (ಜೀವಕ್ಕೆ ಅಪಾಯ)',
      'sos_chip_safe_injured': 'ಗಾಯ, ಸ್ಥಿರ',
      'sos_chip_safe_danger': 'ಗಾಯವಿಲ್ಲ; ಆದರೆ ಅಪಾಯದಲ್ಲಿ',
      'sos_chip_safe_safe_now': 'ಈಗ ಸುರಕ್ಷಿತ',
      'sos_chip_people_me': 'ನಾನು ಮಾತ್ರ',
      'sos_chip_people_two': 'ಇಬ್ಬರು',
      'sos_chip_people_many': 'ಇಬ್ಬರಿಗಿಂತ ಹೆಚ್ಚು',
      'sos_tts_interview_saved':
          'ಬಾಧಿತ ಸಂದರ್ಶನ ಡೇಟಾ ಉಳಿಸಲಾಗಿದೆ. ಪ್ರತಿಕ್ರಿಯಿಸುವವರಿಗೆ ವಿವರಗಳಿವೆ. ಪ್ರತಿ 60 ಸೆಕೆಂಡುಗಳಿಗೆ ಪ್ರಜ್ಞೆ ಪರಿಶೀಲನೆ ಮುಂದುವರಿಯುತ್ತದೆ.',
      'sos_tts_map_routes':
          'ನಕ್ಷೆ ಟ್ಯಾಬ್ ತೆರೆಯಿರಿ: ಕೆಂಪು ನಿಯೋಜಿತ ಆಸ್ಪತ್ರೆಗೆ ರಸ್ತೆ ಮಾರ್ಗ ಅಥವಾ ಹತ್ತಿರದ ಮಾರ್ಗ; ಹಸಿರು ಸ್ವಯಂಸೇವಕ ಮಾರ್ಗ. ತುರ್ತು ಧ್ವನಿ ಚಾನೆಲ್‌ನಲ್ಲಿ ಇರಿ.',
      'sos_tts_emergency_contacts_on_file':
          'Your emergency contact from your profile is attached to this SOS. SMS updates may be sent when that option is enabled.',
      'sos_tts_conscious_no_answer_attempt':
          'ಉತ್ತರವಿಲ್ಲ. ಪ್ರಜ್ಞೆ ಪರಿಶೀಲನೆ {max}ರಲ್ಲಿ {n}. ಒಂದು ನಿಮಿಷದಲ್ಲಿ ಮತ್ತೆ ಕೇಳುತ್ತೇವೆ.',
      'voice_volunteer_accepted':
          'ಸ್ವಯಂಸೇವಕ ಸ್ವೀಕರಿಸಿದರು. ಸಹಾಯ ಮಾರ್ಗದಲ್ಲಿದೆ.',
      'voice_ambulance_dispatched_eta':
          'ಆಂಬ್ಯುಲೆನ್ಸ್ ಕಳುಹಿಸಲಾಗಿದೆ. ಅಂದಾಜು ಆಗಮನ: {eta}.',
      'voice_police_dispatched_eta':
          'ಪೊಲೀಸರನ್ನು ಕಳುಹಿಸಲಾಗಿದೆ. ಅಂದಾಜು ಆಗಮನ: {eta}.',
      'voice_ambulance_on_scene_victim':
          'ಆಂಬ್ಯುಲೆನ್ಸ್ ಸ್ಥಳದಲ್ಲಿದೆ — ನಿಮ್ಮಿಂದ ಸುಮಾರು ಇನ್ನೂರು ಮೀಟರ್ ದೂರ.',
      'voice_ambulance_on_scene_volunteer':
          'ಆಂಬ್ಯುಲೆನ್ಸ್ ಸ್ಥಳದಲ್ಲಿದೆ — ಘಟನಾ ಸ್ಥಳದಿಂದ ಸುಮಾರು ಇನ್ನೂರು ಮೀಟರ್ ಒಳಗೆ.',
      'voice_ambulance_returning': 'ಆಂಬ್ಯುಲೆನ್ಸ್ ಆಸ್ಪತ್ರೆಗೆ ಹಿಂತಿರುಗುತ್ತಿದೆ.',
      'voice_response_complete_station':
          'ಪ್ರತಿಕ್ರಿಯೆ ಪೂರ್ಣ. ಆಂಬ್ಯುಲೆನ್ಸ್ ನಿಲ್ದಾಣದಲ್ಲಿ.',
      'voice_response_complete_cycle':
          'ಪ್ರತಿಕ್ರಿಯೆ ಪೂರ್ಣ. ಆಂಬ್ಯುಲೆನ್ಸ್ ನಿಲ್ದಾಣದಲ್ಲಿ. ಒಟ್ಟು ಚಕ್ರ {minutes} ನಿಮಿಷ {seconds} ಸೆಕೆಂಡು.',
      'voice_volunteers_on_scene_count':
          '{n} ಸ್ವಯಂಸೇವಕರು ಈಗ ಸ್ಥಳದಲ್ಲಿದ್ದಾರೆ.',
      'voice_one_volunteer_on_scene': 'ಒಬ್ಬ ಸ್ವಯಂಸೇವಕ ಸ್ಥಳದಲ್ಲಿದ್ದಾರೆ.',
      'voice_ptt_joined_comms': '{who} ಧ್ವನಿ ಸಂವಹನಕ್ಕೆ ಸೇರಿದರು.',
      'voice_tts_unavailable_banner':
          'ಧ್ವನಿ ಮಾರ್ಗದರ್ಶನ ಲಭ್ಯವಿಲ್ಲ — ಸ್ಕ್ರೀನ್‌ನಲ್ಲಿರುವ ಪಠ್ಯ ಓದಿ.',
      'language_picker_title': 'ಭಾಷೆ',
      'volunteer_victim_medical_card': 'ಬಾಧಿತ ವೈದ್ಯಕೀಯ ಕಾರ್ಡ್',
      'volunteer_dispatch_milestone_title': 'ಡಿಸ್ಪ್ಯಾಚ್ ನವೀಕರಣಗಳು',
      'volunteer_dispatch_milestone_hospital': 'ಆಸ್ಪತ್ರೆ ಸ್ವೀಕರಿಸಿದೆ: {hospital}',
      'volunteer_dispatch_milestone_unit': 'ಆಂಬುಲೆನ್ಸ್ ಘಟಕ: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'ಆಂಬುಲೆನ್ಸ್ ತಂಡ: ಸಮನ್ವಯ…',
      'volunteer_dispatch_milestone_en_route': 'ಆಂಬುಲೆನ್ಸ್ ಮಾರ್ಗದಲ್ಲಿ',
      'volunteer_triage_qr_report_title': 'QR ಅಥವಾ ಟ್ಯಾಪ್ ವರದಿ',
      'volunteer_triage_qr_report_subtitle':
          'ಹ್ಯಾಂಡ್‌ಆಫ್‌ಗಾಗಿ ಕೋಡ್ ಸ್ಕ್ಯಾನ್ ಮಾಡಿ ಅಥವಾ ಘಟನೆಯ ವರದಿಯನ್ನು ಉಳಿಸಲು ಟ್ಯಾಪ್ ಮಾಡಿ.',
      'volunteer_triage_show_qr': 'QR ತೋರಿಸಿ',
      'volunteer_triage_tap_report': 'ವರದಿ',
      'volunteer_triage_qr_title': 'ಘಟನೆ ಹ್ಯಾಂಡ್‌ಆಫ್ QR',
      'volunteer_triage_qr_body': 'ರಚನಾತ್ಮಕ ಡೇಟಾಗಾಗಿ ಸಿಬ್ಬಂದಿ ಅಥವಾ EMS ಜೊತೆ ಹಂಚಿಕೊಳ್ಳಿ.',
      'volunteer_triage_report_saved': 'ವರದಿ ಈ ಘಟನೆಯ ಅಡಿಯಲ್ಲಿ ಉಳಿಸಲಾಗಿದೆ.',
      'volunteer_triage_report_failed': 'ವರದಿಯನ್ನು ಉಳಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ: ',
      'volunteer_victim_medical_offline_hint': 'SOS ಪ್ಯಾಕೆಟ್‌ನಿಂದ — ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿ ಕ್ಯಾಶ್‌ನಿಂದ.',
      'volunteer_victim_consciousness_title': 'ಪ್ರಜ್ಞೆ',
      'volunteer_victim_three_questions': 'ಆರಂಭಿಕ ಉತ್ತರಗಳು',
      'volunteer_major_updates_log': 'ಪ್ರಮುಖ ನವೀಕರಣಗಳು ಮಾತ್ರ',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'ಟಿಯರ್ {tier} ಗೆ ಏರಿಸುತ್ತಿದ್ದೇವೆ. ಆಸ್ಪತ್ರೆ {hospital} ಪ್ರಯತ್ನಿಸುತ್ತಿದ್ದೇವೆ.',
      'volunteer_dispatch_trying_hospital': 'ಆಸ್ಪತ್ರೆ {hospital} ಪ್ರಯತ್ನಿಸುತ್ತಿದ್ದೇವೆ.',
      'volunteer_dispatch_hospital_accepted':
          '{hospital} ತುರ್ತನ್ನು ಸ್ವೀಕರಿಸಿದೆ. ಆಂಬುಲೆನ್ಸ್ ಸಮನ್ವಯ ನಡೆಯುತ್ತಿದೆ.',
      'volunteer_dispatch_all_hospitals_notified':
          'ಎಲ್ಲಾ ಆಸ್ಪತ್ರೆಗಳಿಗೆ ತಿಳಿಸಲಾಗಿದೆ. ತುರ್ತು ಸೇವೆಗಳಿಗೆ ಮುಂದಕ್ಕೆ ಕಳುಹಿಸುತ್ತಿದ್ದೇವೆ.',
      'sos_dispatch_alerting_nearest_trying':
          'ನಿಮ್ಮ ಪ್ರದೇಶದ ಹತ್ತಿರದ ಆಸ್ಪತ್ರೆಗೆ ಎಚ್ಚರಿಕೆ. {hospital} ಪ್ರಯತ್ನಿಸುತ್ತಿದ್ದೇವೆ.',
      'sos_dispatch_escalating_tier_trying':
          'ಪ್ರತಿಕ್ರಿಯೆ ಇಲ್ಲ. ಟಿಯರ್ {tier} ಗೆ ಏರಿಸುತ್ತಿದ್ದೇವೆ. {hospital} ಪ್ರಯತ್ನಿಸುತ್ತಿದ್ದೇವೆ.',
      'sos_dispatch_retry_previous_trying':
          'ಹಿಂದಿನ ಆಸ್ಪತ್ರೆಯಿಂದ ಪ್ರತಿಕ್ರಿಯೆ ಇಲ್ಲ. {hospital} ಪ್ರಯತ್ನಿಸುತ್ತಿದ್ದೇವೆ.',
      'sos_dispatch_all_hospitals_call_112':
          'ಎಲ್ಲಾ ಆಸ್ಪತ್ರೆಗಳಿಗೆ ತಿಳಿಸಲಾಗಿದೆ. ತುರ್ತು ಸೇವೆಗಳಿಗೆ ದಯವಿಟ್ಟು 112 ಗೆ ಕರೆ ಮಾಡಿ.',
      'sos_active_title_big': 'ಸಕ್ರಿಯ SOS',
      'sos_active_help_coming': 'ಸಹಾಯ ಬರುತ್ತಿದೆ. ಶಾಂತವಾಗಿರಿ.',
      'sos_active_badge_waiting': 'ನಿರೀಕ್ಷೆ',
      'sos_active_badge_en_route_count': '{n} ದಾರಿಯಲ್ಲಿ',
      'sos_active_mini_ambulance': 'ಆಂಬ್ಯುಲೆನ್ಸ್',
      'sos_active_mini_on_scene': 'ಸ್ಥಳದಲ್ಲಿ',
      'sos_active_mini_status': 'ಸ್ಥಿತಿ',
      'sos_active_volunteers_count_short': '{n} ಸ್ವಯಂಸೇವಕರು',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title':
          'ಎಲ್ಲಾ ಆಸ್ಪತ್ರೆಗಳಿಗೆ ತಿಳಿಸಲಾಗಿದೆ',
      'sos_active_all_hospitals_notified_subtitle':
          'ಸಮಯಕ್ಕೆ ಯಾವುದೇ ಆಸ್ಪತ್ರೆ ಸ್ವೀಕರಿಸಲಿಲ್ಲ. ತುರ್ತು ಸೇವೆಗಳಿಗೆ ಡಿಸ್ಪಾಚ್ ಹೆಚ್ಚಿಸುತ್ತಿದೆ.',
      'sos_active_position_refresh_note':
          'ಬ್ಯಾಟರಿ ಉಳಿಸಲು SOS ಸಮಯದಲ್ಲಿ ನಿಮ್ಮ ಸ್ಥಳವನ್ನು ಸುಮಾರು 45 ಸೆಕೆಂಡ್‌ಗಳಿಗೊಮ್ಮೆ ನವೀಕರಿಸಲಾಗುತ್ತದೆ. ಅಪ್ಲಿಕೇಶನ್ ತೆರೆದಿಡಿ ಮತ್ತು ಸಾಧ್ಯವಾದರೆ ಚಾರ್ಜ್ ಮಾಡಿ.',
      'sos_active_mic_active': 'ಮೈಕ್ · ಸಕ್ರಿಯ',
      'sos_active_mic_active_detail':
          'ಲೈವ್ ಚಾನೆಲ್ ನಿಮ್ಮ ಮೈಕ್ರೋಫೋನ್ ಅನ್ನು ಸ್ವೀಕರಿಸುತ್ತಿದೆ.',
      'sos_active_mic_standby': 'ಮೈಕ್ · ಸ್ಟ್ಯಾಂಡ್‌ಬೈ',
      'sos_active_mic_standby_detail': 'ಧ್ವನಿ ಚಾನೆಲ್‌ಗಾಗಿ ಕಾಯುತ್ತಿದೆ…',
      'sos_active_mic_connecting': 'ಮೈಕ್ · ಸಂಪರ್ಕಿಸಲಾಗುತ್ತಿದೆ',
      'sos_active_mic_connecting_detail':
          'ತುರ್ತು ಧ್ವನಿ ಚಾನೆಲ್‌ಗೆ ಸೇರಲಾಗುತ್ತಿದೆ…',
      'sos_active_mic_reconnecting': 'ಮೈಕ್ · ಮರುಸಂಪರ್ಕ',
      'sos_active_mic_reconnecting_detail':
          'ಲೈವ್ ಆಡಿಯೋವನ್ನು ಪುನಃಸ್ಥಾಪಿಸಲಾಗುತ್ತಿದೆ…',
      'sos_active_mic_failed': 'ಮೈಕ್ · ಅಡ್ಡಿ',
      'sos_active_mic_failed_detail':
          'ಧ್ವನಿ ಚಾನೆಲ್ ಲಭ್ಯವಿಲ್ಲ. ಮೇಲೆ RETRY ಬಳಸಿ.',
      'sos_active_mic_ptt_only': 'ಮೈಕ್ · ಘಟನೆ ಚಾನೆಲ್',
      'sos_active_mic_ptt_only_detail':
          'ಕಾರ್ಯಾಚರಣೆ ಕನ್ಸೋಲ್ Firebase PTT ಮೂಲಕ ಧ್ವನಿಯನ್ನು ರೂಟ್ ಮಾಡಿದೆ. ಸ್ಪಂದಿಸುವವರನ್ನು ತಲುಪಲು ಬ್ರಾಡ್‌ಕಾಸ್ಟ್ ಅನ್ನು ಹಿಡಿಯಿರಿ.',
      'sos_active_mic_interrupted': 'ಮೈಕ್ · ಅಡಚಣೆ',
      'sos_active_mic_interrupted_detail':
          'ಅಪ್ಲಿಕೇಶನ್ ಆಡಿಯೋ ಸಂಸ್ಕರಿಸುವಾಗ ಚಿಕ್ಕ ವಿರಾಮ.',
      'sos_active_consciousness_note':
          'ಪ್ರಜ್ಞೆ ಪರಿಶೀಲನೆಗೆ ಹೌದು ಅಥವಾ ಇಲ್ಲ ಎಂದು ಉತ್ತರಿಸಿ; ಇತರ ಪ್ರಾಂಪ್ಟ್‌ಗಳು ಸ್ಕ್ರೀನ್ ಆಯ್ಕೆಗಳನ್ನು ಬಳಸುತ್ತವೆ.',
      'sos_active_live_updates_header': 'ಲೈವ್ ನವೀಕರಣಗಳು',
      'sos_active_live_updates_subtitle':
          'ಡಿಸ್ಪಾಚ್, ಸ್ವಯಂಸೇವಕರು ಮತ್ತು ಸಾಧನ',
      'sos_active_live_tag': 'ಲೈವ್',
      'sos_active_activity_log': 'ಚಟುವಟಿಕೆ ಲಾಗ್',
      'sos_active_header_stat_coordinating_crew': 'ಸಿಬ್ಬಂದಿ ಸಮನ್ವಯ',
      'sos_active_header_stat_coordinating': 'ಸಮನ್ವಯ',
      'sos_active_header_stat_en_route': 'ಮಾರ್ಗದಲ್ಲಿ',
      'sos_active_header_stat_route_min': '~{n} ನಿಮಿ',
      'sos_active_live_sos_is_live_title': 'SOS ಲೈವ್‌ನಲ್ಲಿದೆ',
      'sos_active_live_sos_is_live_detail':
          'ನಿಮ್ಮ ಸ್ಥಳ ಮತ್ತು ವೈದ್ಯಕೀಯ ಫ್ಲ್ಯಾಗ್‌ಗಳು ತುರ್ತು ನೆಟ್‌ವರ್ಕ್‌ನಲ್ಲಿವೆ.',
      'sos_active_live_volunteers_notified_title':
          'ಸ್ವಯಂಸೇವಕರಿಗೆ ತಿಳಿಸಲಾಗಿದೆ',
      'sos_active_live_volunteers_notified_detail':
          'ಹತ್ತಿರದ ಸ್ವಯಂಸೇವಕರು ಈ ಘಟನೆಯನ್ನು ನೈಜ ಸಮಯದಲ್ಲಿ ಸ್ವೀಕರಿಸುತ್ತಾರೆ.',
      'sos_active_live_bridge_connected_title':
          'ತುರ್ತು ಧ್ವನಿ ಸೇತುವೆ ಸಂಪರ್ಕ',
      'sos_active_live_bridge_connected_detail':
          'ಡಿಸ್ಪಾಚ್ ಡೆಸ್ಕ್ ಮತ್ತು ಸ್ಪಂದಿಸುವವರು ಈ ಚಾನೆಲ್ ಕೇಳಬಹುದು.',
      'sos_active_live_ptt_title': 'Firebase PTT ಮೂಲಕ ಧ್ವನಿ',
      'sos_active_live_ptt_detail':
          'ಈ ಫ್ಲೀಟ್‌ಗೆ ಲೈವ್ WebRTC ಸೇತುವೆ ಆಫ್ ಆಗಿದೆ. ಧ್ವನಿ ಮತ್ತು ಪಠ್ಯ ನವೀಕರಣಗಳಿಗೆ ಬ್ರಾಡ್‌ಕಾಸ್ಟ್ ಬಳಸಿ.',
      'sos_active_live_contacts_notified_title':
          'ತುರ್ತು ಸಂಪರ್ಕಗಳಿಗೆ ತಿಳಿಸಲಾಗಿದೆ',
      'sos_active_live_hospital_accepted_title': 'ಆಸ್ಪತ್ರೆ ಸ್ವೀಕರಿಸಿದೆ',
      'sos_active_live_ambulance_unit_assigned_title':
          'ಆಂಬ್ಯುಲೆನ್ಸ್ ಘಟಕ ನಿಯೋಜಿಸಲಾಗಿದೆ',
      'sos_active_live_ambulance_unit_assigned_subtitle': 'ಘಟಕ {unit}',
      'sos_active_live_ambulance_en_route_title': 'ಆಂಬ್ಯುಲೆನ್ಸ್ ದಾರಿಯಲ್ಲಿ',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'ದಾರಿಯಲ್ಲಿ',
      'sos_active_live_ambulance_en_route_route_eta': '~{n} ನಿಮಿ (ಮಾರ್ಗ)',
      'sos_active_live_ambulance_coordination_title': 'ಆಂಬ್ಯುಲೆನ್ಸ್ ಸಮನ್ವಯ',
      'sos_active_live_ambulance_coordination_pending':
          'ಆಸ್ಪತ್ರೆ ಸ್ವೀಕರಿಸಿದೆ — ಆಂಬ್ಯುಲೆನ್ಸ್ ಆಪರೇಟರ್‌ಗಳಿಗೆ ತಿಳಿಸಲಾಗುತ್ತಿದೆ.',
      'sos_active_live_ambulance_coordination_arranging':
          'ಆಂಬ್ಯುಲೆನ್ಸ್ ಸಿಬ್ಬಂದಿ ಏರ್ಪಾಡು — ಘಟಕ ದಾರಿಯಲ್ಲಿದ್ದಾಗ ನಿಮಿಷಗಳ ETA.',
      'sos_active_live_responder_status_title': 'ಸ್ಪಂದಿಸುವವರ ಸ್ಥಿತಿ',
      'sos_active_live_volunteer_accepted_single_title':
          'ಸ್ವಯಂಸೇವಕ ಸ್ವೀಕರಿಸಿದ್ದಾರೆ',
      'sos_active_live_volunteer_accepted_many_title':
          'ಸ್ವಯಂಸೇವಕರು ಸ್ವೀಕರಿಸಿದ್ದಾರೆ',
      'sos_active_live_volunteer_accepted_single_detail':
          'ಒಬ್ಬ ಸ್ಪಂದಿಸುವವರು ನಿಯೋಜಿಸಲಾಗಿದ್ದಾರೆ ಮತ್ತು ನಿಮಗೆ ಸಹಾಯ ಮಾಡಲು ಬರುತ್ತಿದ್ದಾರೆ.',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} ಸ್ಪಂದಿಸುವವರು ಈ SOS ಗೆ ನಿಯೋಜಿಸಲಾಗಿದ್ದಾರೆ.',
      'sos_active_live_volunteer_on_scene_single_title':
          'ಸ್ವಯಂಸೇವಕ ಸ್ಥಳಕ್ಕೆ ತಲುಪಿದ್ದಾರೆ',
      'sos_active_live_volunteer_on_scene_many_title':
          'ಸ್ವಯಂಸೇವಕರು ಸ್ಥಳದಲ್ಲಿ',
      'sos_active_live_volunteer_on_scene_single_detail':
          'ಯಾರೋ ನಿಮ್ಮೊಂದಿಗೆ ಅಥವಾ ನಿಮ್ಮ ಪಿನ್‌ನಲ್ಲಿದ್ದಾರೆ.',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} ಸ್ಪಂದಿಸುವವರು ಸ್ಥಳದಲ್ಲಿ ಗುರುತಿಸಲಾಗಿದೆ.',
      'sos_active_live_responder_location_title':
          'ಲೈವ್ ಸ್ಪಂದಿಸುವವರ ಸ್ಥಳ',
      'sos_active_live_responder_location_detail':
          'ನಿಯೋಜಿಸಲಾದ ಸ್ವಯಂಸೇವಕ GPS ನಕ್ಷೆಯಲ್ಲಿ ನವೀಕರಿಸುತ್ತಿದೆ.',
      'sos_active_live_professional_dispatch_title':
          'ವೃತ್ತಿಪರ ಡಿಸ್ಪಾಚ್ ಸಕ್ರಿಯ',
      'sos_active_live_professional_dispatch_detail':
          'ಸಮನ್ವಯ ಸೇವೆಗಳು ಈ ಘಟನೆಯಲ್ಲಿ ಕೆಲಸ ಮಾಡುತ್ತಿವೆ.',
      'sos_active_ambulance_200m_detail':
          'ಆಂಬ್ಯುಲೆನ್ಸ್ ಸ್ಥಳದಲ್ಲಿ — ಸುಮಾರು 200 ಮೀಟರ್ ಒಳಗೆ.',
      'sos_active_ambulance_200m_semantic_label':
          'ಆಂಬ್ಯುಲೆನ್ಸ್ ಸುಮಾರು ಇನ್ನೂರು ಮೀಟರ್ ಒಳಗೆ ಸ್ಥಳದಲ್ಲಿ',
      'sos_active_bridge_channel_on_suffix': ' · {n} ಚಾನೆಲ್‌ನಲ್ಲಿ',
      'sos_active_bridge_channel_voice': 'ತುರ್ತು ಧ್ವನಿ ಚಾನೆಲ್',
      'sos_active_bridge_channel_ptt': 'ತುರ್ತು ಚಾನೆಲ್ · Firebase PTT',
      'sos_active_bridge_channel_failed':
          'ತುರ್ತು ಚಾನೆಲ್ · ಮರುಪ್ರಯತ್ನಿಸಿ',
      'sos_active_bridge_channel_connecting':
          'ತುರ್ತು ಚಾನೆಲ್ · ಸಂಪರ್ಕಿಸಲಾಗುತ್ತಿದೆ',
      'sos_active_dispatch_contact_hospitals_default':
          'ನಿಮ್ಮ ಸ್ಥಳ ಮತ್ತು ತುರ್ತು ಪ್ರಕಾರದ ಆಧಾರದ ಮೇಲೆ ಹತ್ತಿರದ ಆಸ್ಪತ್ರೆಗಳನ್ನು ಸಂಪರ್ಕಿಸುತ್ತಿದ್ದೇವೆ.',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'ಆಂಬ್ಯುಲೆನ್ಸ್ ಸಿಬ್ಬಂದಿಗೆ ತಿಳಿಸಲಾಗಿದೆ',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'ಪಾಲುದಾರ ಆಸ್ಪತ್ರೆ ನಿಮ್ಮ ಪ್ರಕರಣವನ್ನು ಸ್ವೀಕರಿಸಿದೆ. ಆಂಬ್ಯುಲೆನ್ಸ್ ಆಪರೇಟರ್‌ಗಳಿಗೆ ತಿಳಿಸಲಾಗುತ್ತಿದೆ.',
      'sos_active_dispatch_ambulance_confirmed_title':
          'ಆಂಬ್ಯುಲೆನ್ಸ್ ದೃಢೀಕರಣ',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'ಘಟಕ {unit} ನಿಮ್ಮೆಡೆಗೆ ಬರುತ್ತಿದೆ. ಸ್ಪಂದಿಸುವವರು ತಲುಪುವ ಸ್ಥಳದಲ್ಲಿ ಇರಿ.',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'ಒಂದು ಆಂಬ್ಯುಲೆನ್ಸ್ ನಿಮ್ಮೆಡೆಗೆ ಬರುತ್ತಿದೆ. ಸ್ಪಂದಿಸುವವರು ತಲುಪುವ ಸ್ಥಳದಲ್ಲಿ ಇರಿ.',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'ಆಂಬ್ಯುಲೆನ್ಸ್ ಹ್ಯಾಂಡ್‌ಆಫ್ ವಿಳಂಬ',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'ಆಸ್ಪತ್ರೆ ಸ್ವೀಕರಿಸಿದೆ, ಆದರೆ ಸಮಯಕ್ಕೆ ಆಂಬ್ಯುಲೆನ್ಸ್ ಸಿಬ್ಬಂದಿ ದೃಢಪಡಿಸಲಿಲ್ಲ. ಡಿಸ್ಪಾಚ್ ಹೆಚ್ಚಿಸುತ್ತಿದೆ — ಅಗತ್ಯವಿದ್ದರೆ 112 ಕ್ಕೆ ಕರೆ ಮಾಡಿ.',
      'sos_active_dispatch_pending_title_trying': 'ಪ್ರಯತ್ನ: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · ಆಸ್ಪತ್ರೆ ಪ್ರತಿಕ್ರಿಯೆಗಾಗಿ ಕಾಯುತ್ತಿದೆ.',
      'sos_active_dispatch_accepted_title': '{hospital} ಸ್ವೀಕರಿಸಿದೆ',
      'sos_active_dispatch_accepted_subtitle':
          'ಆಂಬ್ಯುಲೆನ್ಸ್ ಡಿಸ್ಪಾಚ್ ಸಮನ್ವಯ ಮಾಡಲಾಗುತ್ತಿದೆ.',
      'sos_active_dispatch_exhausted_title':
          'ಎಲ್ಲಾ ಆಸ್ಪತ್ರೆಗಳಿಗೆ ತಿಳಿಸಲಾಗಿದೆ',
      'sos_active_dispatch_exhausted_subtitle':
          'ಸಮಯಕ್ಕೆ ಯಾವುದೇ ಆಸ್ಪತ್ರೆ ಸ್ವೀಕರಿಸಲಿಲ್ಲ. ತುರ್ತು ಸೇವೆಗಳಿಗೆ ಡಿಸ್ಪಾಚ್ ಹೆಚ್ಚಿಸುತ್ತಿದೆ.',
      'sos_active_dispatch_generic_title': 'ಆಸ್ಪತ್ರೆ ಡಿಸ್ಪಾಚ್',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'ತುರ್ತು ಧ್ವನಿ ಚಾನೆಲ್',
      'volunteer_bridge_join_hint_incident':
          'ಸೇರಲು ಈ ಘಟನೆಯನ್ನು ಬಳಸಲಾಗುತ್ತದೆ: ನಿಮ್ಮ ಸಂಖ್ಯೆ ಹೊಂದಿಕೆಯಾದರೆ ತುರ್ತು ಸಂಪರ್ಕ; ಇಲ್ಲದಿದ್ದರೆ ಸ್ವೀಕೃತ ಸ್ವಯಂಸೇವಕ.',
      'volunteer_bridge_join_hint_elite':
          'ನೀವು ಸ್ವೀಕೃತ ಸ್ಪಂದಿಸುವವರಾಗಿದ್ದಾಗ ಸೇರುವಿಕೆ ನಿಮ್ಮ ಎಲೈಟ್ ಪ್ರವೇಶವನ್ನು ಬಳಸುತ್ತದೆ; ಇಲ್ಲದಿದ್ದರೆ ನಿಮ್ಮ ಸಂಖ್ಯೆ ಹೊಂದಿಕೆಯಾದಾಗ ಸಂಪರ್ಕ.',
      'volunteer_bridge_join_hint_desk':
          'ನಿಮ್ಮ ಪ್ರೊಫೈಲ್‌ನಲ್ಲಿರುವ ತುರ್ತು ಸೇವೆಗಳ ಡೆಸ್ಕ್ ಆಗಿ ನೀವು ಡಿಸ್ಪಾಚ್ ಆಗಿ ಸೇರುತ್ತೀರಿ.',
      'volunteer_bridge_join_voice_btn': 'ಧ್ವನಿಯಲ್ಲಿ ಸೇರಿ',
      'volunteer_bridge_connecting_btn': 'ಸಂಪರ್ಕಿಸಲಾಗುತ್ತಿದೆ…',
      'volunteer_bridge_incident_id_hint': 'ಘಟನೆ ID',
      'volunteer_consignment_live_location_hint':
          'ನೀವು ಕನ್ಸೈನ್ಮೆಂಟ್‌ನಲ್ಲಿರುವಾಗ, ನಕ್ಷೆ ಮತ್ತು ETA ನಿಖರವಾಗಿ ಉಳಿಯಲು ನಿಮ್ಮ ಲೈವ್ ಸ್ಥಳ ಈ ಘಟನೆಯೊಂದಿಗೆ ಹಂಚಲಾಗಿದೆ.',
      'volunteer_consignment_low_power_label': 'ಕಡಿಮೆ ಪವರ್',
      'volunteer_consignment_normal_gps_label': 'ಸಾಮಾನ್ಯ GPS',
      'bridge_card_incident_id_missing': 'ಘಟನೆ ID ಇಲ್ಲ.',
      'bridge_card_ptt_only_snackbar':
          'ಕಾರ್ಯಾಚರಣಾ ಕನ್ಸೋಲ್ ಬಲಿಯ ಧ್ವನಿಯನ್ನು Firebase PTT ಮೂಲಕ ರೂಟ್ ಮಾಡಿದೆ. WebRTC ಸೇತುವೆ ಸೇರ್ಪಡೆ ನಿಷ್ಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.',
      'bridge_card_ptt_only_banner':
          'ಕನ್ಸೋಲ್ Firebase PTT ಮೂಲಕ ಧ್ವನಿ ಕಳುಹಿಸಿತು — ಈ ಫ್ಲೀಟ್‌ಗಾಗಿ LiveKit ಸೇತುವೆ ಸೇರ್ಪಡೆ ನಿಷ್ಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.',
      'bridge_card_connected_snackbar': 'ಧ್ವನಿ ಚಾನೆಲ್‌ಗೆ ಸಂಪರ್ಕಿಸಲಾಗಿದೆ.',
      'bridge_card_could_not_join': 'ಸೇರಲಾಗಲಿಲ್ಲ: {err}',
      'bridge_card_voice_channel_title': 'ಧ್ವನಿ ಚಾನೆಲ್',
      'bridge_card_calm_disclaimer':
          'ಶಾಂತವಾಗಿರಿ ಮತ್ತು ಸ್ಪಷ್ಟವಾಗಿ ಮಾತನಾಡಿ. ಸ್ಥಿರ ಧ್ವನಿ ಸಂತ್ರಸ್ತ ಮತ್ತು ಇತರ ಸಹಾಯಕರಿಗೆ ಸಹಾಯ ಮಾಡುತ್ತದೆ. ಅರಚಬೇಡಿ, ಪದಗಳನ್ನು ಅವಸರಿಸಬೇಡಿ.',
      'bridge_card_cancel': 'ರದ್ದು',
      'bridge_card_join_voice': 'ಧ್ವನಿಯಲ್ಲಿ ಸೇರಿ',
      'bridge_card_voice_connected': 'ಧ್ವನಿ ಸಂಪರ್ಕಿತ',
      'bridge_card_in_channel': 'ಚಾನೆಲ್‌ನಲ್ಲಿ {n} ಜನ',
      'bridge_card_transmitting': 'ಪ್ರಸಾರವಾಗುತ್ತಿದೆ…',
      'bridge_card_hold_to_talk': 'ಮಾತನಾಡಲು ಹಿಡಿದುಕೊಳ್ಳಿ',
      'bridge_card_disconnect': 'ಸಂಪರ್ಕ ಕಡಿತ',
      'vol_ems_banner_en_route': 'ಆಂಬ್ಯುಲೆನ್ಸ್ ಘಟನಾ ಸ್ಥಳಕ್ಕೆ ಮಾರ್ಗದಲ್ಲಿ',
      'vol_ems_banner_on_scene': 'ಆಂಬ್ಯುಲೆನ್ಸ್ ಸ್ಥಳದಲ್ಲಿ (~200 ಮೀ)',
      'vol_ems_banner_returning': 'ಆಂಬ್ಯುಲೆನ್ಸ್ ಆಸ್ಪತ್ರೆಗೆ ಹಿಂತಿರುಗುತ್ತಿದೆ',
      'vol_ems_banner_complete': 'ಪ್ರತಿಕ್ರಿಯೆ ಪೂರ್ಣ · ಆಂಬ್ಯುಲೆನ್ಸ್ ಸ್ಟೇಷನ್‌ನಲ್ಲಿ',
      'vol_ems_banner_complete_with_cycle':
          'ಪ್ರತಿಕ್ರಿಯೆ ಪೂರ್ಣ · ಆಂಬ್ಯುಲೆನ್ಸ್ ಸ್ಟೇಷನ್‌ನಲ್ಲಿ · ಒಟ್ಟು ಚಕ್ರ {m}ನಿ {s}ಸೆ',
      'vol_tooltip_lifeline_first_aid':
          'ಲೈಫ್‌ಲೈನ್ — ಪ್ರಥಮ ಚಿಕಿತ್ಸಾ ಮಾರ್ಗಸೂಚಿಗಳು (ಪ್ರತಿಕ್ರಿಯೆಯಲ್ಲಿ ಇರುತ್ತದೆ)',
      'vol_tooltip_exit_mission': 'ಮಿಷನ್ ನಿರ್ಗಮನ',
      'vol_low_power_tracking_hint':
          'ಕಡಿಮೆ-ಶಕ್ತಿ ಟ್ರ್ಯಾಕಿಂಗ್: ನಿಮ್ಮ ಸ್ಥಾನವನ್ನು ಕಡಿಮೆ ಬಾರಿ, ದೊಡ್ಡ ಚಲನೆಗಳ ನಂತರ ಮಾತ್ರ ಸಿಂಕ್ ಮಾಡುತ್ತೇವೆ. ಡಿಸ್ಪಾಚ್ ನಿಮ್ಮ ಕೊನೆಯ ಬಿಂದುವನ್ನು ನೋಡುತ್ತದೆ.',
      'vol_marker_you': 'ನೀವು',
      'vol_marker_active_unit': 'ಸಕ್ರಿಯ ಘಟಕ',
      'vol_marker_practice_incident': 'ಅಭ್ಯಾಸ ಘಟನೆ',
      'vol_marker_accident_scene': 'ಅಪಘಾತ ಸ್ಥಳ',
      'vol_marker_training_pin': 'ತರಬೇತಿ ಪಿನ್ — ನಿಜವಾದ SOS ಅಲ್ಲ',
      'vol_marker_high_severity': 'GITM ಕಾಲೇಜು - ಅಧಿಕ ತೀವ್ರತೆ',
      'vol_marker_accepted_hospital': 'ಸ್ವೀಕೃತ: {hospital}',
      'vol_marker_trying_hospital': 'ಪ್ರಯತ್ನ: {hospital}',
      'vol_marker_ambulance_on_scene': 'ಆಂಬ್ಯುಲೆನ್ಸ್ ಸ್ಥಳದಲ್ಲಿ!',
      'vol_marker_ambulance_en_route': 'ಆಂಬ್ಯುಲೆನ್ಸ್ ಮಾರ್ಗದಲ್ಲಿ',
      'vol_badge_at_scene_pin': 'ಸ್ಥಳ ಪಿನ್‌ನಲ್ಲಿ',
      'vol_badge_in_5km_zone': '5 ಕಿಮೀ ವಲಯದಲ್ಲಿ',
      'vol_badge_en_route': 'ಮಾರ್ಗದಲ್ಲಿ',
    },

    // ── Malayalam (മലയാളം) ─────────────────────────────────────────────────
    'ml': {
      'app_name': 'EmergencyOS',
      'profile_title': 'പ്രൊഫൈൽ & മെഡിക്കൽ ഐഡി',
      'language': 'ഭാഷ',
      'save_medical_profile': 'മെഡിക്കൽ പ്രൊഫൈൽ സേവ് ചെയ്യുക',
      'critical_medical_info': 'നിർണായക മെഡിക്കൽ വിവരങ്ങൾ',
      'emergency_contacts': 'അടിയന്തര ബന്ധങ്ങൾ',
      'golden_hour_details': 'ഗോൾഡൻ അവർ വിശദാംശങ്ങൾ',
      'sos_lock': 'SOS ലോക്ക്',
      'top_life_savers': 'മികച്ച ജീവൻ രക്ഷകർ',
      'lives_saved': 'രക്ഷിച്ച ജീവനുകൾ',
      'active_alerts': 'സജീവ അലേർട്ടുകൾ',
      'rank': 'റാങ്ക്',
      'on_duty': 'ഡ്യൂട്ടിയിൽ',
      'standby': 'സ്റ്റാൻഡ്ബൈ',
      'sos': 'SOS',
      'call_now': 'ഇപ്പോൾ വിളിക്കുക',
      'quick_guide': 'ദ്രുത ഗൈഡ്',
      'detailed_instructions': 'വിശദമായ നിർദ്ദേശങ്ങൾ',
      'red_flags': 'അപകട സൂചനകൾ',
      'cautions': 'മുന്നറിയിപ്പുകൾ',
      'voice_walkthrough': 'വോയ്‌സ് വഴികാട്ടി',
      'playing': 'പ്ലേ ചെയ്യുന്നു...',
      'swipe_next_guide': 'അടുത്ത ഗൈഡിലേക്ക് സ്വൈപ്പ് ചെയ്യുക',
      'watch_video_guide': 'പൂർണ വീഡിയോ ഗൈഡ് കാണുക',
      'emergency_grid_scan': 'അടിയന്തര ഗ്രിഡ് സ്കാൻ',
      'area_telemetry': 'ഏരിയ ടെലിമെട്രി & അപകട സൂചിക',
      'report_hazard': 'അപകടം റിപ്പോർട്ട് ചെയ്യുക',
      'todays_duty': 'ഇന്നത്തെ ഡ്യൂട്ടി',
      'blood_type': 'രക്ത ഗ്രൂപ്പ്',
      'allergies': 'അലർജികൾ',
      'medical_conditions': 'മെഡിക്കൽ അവസ്ഥകൾ',
      'contact_name': 'പ്രാഥമിക ബന്ധപ്പെടേണ്ട പേര്',
      'contact_phone': 'പ്രാഥമിക ബന്ധപ്പെടേണ്ട ഫോൺ',
      'relationship': 'ബന്ധം',
      'medications': 'നിലവിലെ മരുന്നുകൾ',
      'organ_donor': 'അവയവ ദാന നില',
      'good_morning': 'സുപ്രഭാതം,',
      'good_afternoon': 'ശുഭ ഉച്ചയ്ക്ക്,',
      'good_evening': 'ശുഭ സന്ധ്യ,',
      'hospitals': 'ആശുപത്രികൾ',
      'visual_walkthrough': 'വിഷ്വൽ വഴികാട്ടി',
      'lifeline': 'ലൈഫ്‌ലൈൻ',
      'nav_home': 'ഹോം',
      'nav_map': 'മാപ്പ്',
      'nav_grid': 'ഗ്രിഡ്',
      'nav_profile': 'പ്രൊഫൈൽ',
      'map_caching_offline_pct': 'ഓഫ്‌ലൈനായി പ്രദേശം കാഷ് ചെയ്യുന്നു — {pct}%',
      'map_drill_practice_banner':
          'പരിശീലന ഗ്രിഡ്: പൾസിംഗ് പിൻ = ഡെമോ സജീവ അലേർട്ടുകൾ. ലെയറുകൾക്ക് മാപ്പ് ഫിൽട്ടറുകൾ — യഥാർത്ഥ ഡാറ്റ അല്ല.',
      'map_recenter_tooltip': 'വീണ്ടും കേന്ദ്രീകരിക്കുക',
      'map_legend_hospital': 'ആശുപത്രി',
      'map_legend_live_sos_history': 'ലൈവ് SOS / ചരിത്രം',
      'map_legend_past_this_hex': 'കഴിഞ്ഞ (ഈ ഹെക്സ്)',
      'map_legend_in_area': 'പ്രദേശത്ത് {n}',
      'map_legend_in_cell': 'സെല്ലിൽ {n}',
      'map_legend_volunteers_on_duty': 'ഡ്യൂട്ടിയിലെ സ്വയംസേവകർ',
      'map_legend_volunteers_in_grid': 'ഗ്രിഡിൽ {n}',
      'map_legend_responder_scene': 'പ്രതികരണക്കാരൻ → ദൃശ്യം',
      'map_responder_routes_one': '{n} പാത',
      'map_responder_routes_many': '{n} പാതകൾ',
      'map_filters_title': 'മാപ്പ് ഫിൽട്ടറുകൾ',
      'step_prefix': 'ഘട്ടം',
      'highlights_steps': 'ഓരോന്നായി ഘട്ടങ്ങൾ കാണിക്കുന്നു',
      'offline_mode': 'ഓഫ്‌ലൈൻ — നെറ്റ്‌വർക്ക് വിച്ഛേദിച്ചു',
      'volunteer': 'സന്നദ്ധ പ്രവർത്തകൻ',
      'unranked': 'റാങ്ക് ഇല്ല',
      'live': 'ലൈവ്',
      'you': 'നിങ്ങൾ',
      'saved': 'രക്ഷിച്ചു',
      'xp_responses': 'XP · {0} പ്രതികരണങ്ങൾ',
      'duty_monitoring': 'നിങ്ങൾ ഡ്യൂട്ടിയിൽ ആയിരിക്കുമ്പോൾ SOS പോപ്പ്-അപ്പുകൾ ഓണാണ്.',
      'turn_on_duty_msg': 'SOS പോപ്പ്-അപ്പുകൾ ലഭിക്കാൻ ഡ്യൂട്ടി ഓണാക്കുക.',
      'on_duty_snack': 'ഡ്യൂട്ടിയിൽ — നിങ്ങളുടെ പ്രദേശത്ത് സംഭവങ്ങൾ നിരീക്ഷിക്കുന്നു...',
      'off_duty_snack': 'സ്റ്റാൻഡ്ബൈ — ഡ്യൂട്ടി സെഷൻ രേഖപ്പെടുത്തി.',
      'leaderboard_offline': 'ലീഡർബോർഡ് ഓഫ്‌ലൈൻ',
      'leaderboard_offline_sub': 'സിങ്ക് നിർത്തി. കാഷ് സ്കോറുകൾ.',
      'set_sos_pin_first': 'ആദ്യം SOS പിൻ സെറ്റ് ചെയ്യുക',
      'set_pin_safety_msg': 'സുരക്ഷയ്ക്കായി, SOS സൃഷ്ടിക്കുന്നതിന് മുമ്പ് പിൻ സെറ്റ് ചെയ്യണം.',
      'set_pin_now': 'ഇപ്പോൾ പിൻ സെറ്റ് ചെയ്യുക',
      'later': 'പിന്നീട്',
      'sos_are_you_conscious':
          'നിങ്ങൾ ബോധമുണ്ടോ? ദയവായി അതെ അല്ലെങ്കിൽ ഇല്ല എന്ന് മറുപടി പറയുക.',
      'sos_tts_opening_guidance':
          'നിങ്ങളുടെ SOS സജീവമാണ്. സഹായം വരുന്നു. സംസാര നിർദ്ദേശങ്ങൾ പാലിച്ച് മറുപടി നൽകാൻ ടാപ്പ് ചെയ്യുക.',
      'sos_interview_q1_prompt': 'എന്താണ് സംഭവിക്കുന്നത്? (അടിയന്തര തരം)',
      'sos_interview_q2_prompt': 'നിങ്ങൾ സുരക്ഷിതരാണോ? എത്ര ഗുരുതരം?',
      'sos_interview_q3_prompt': 'എത്ര പേർ ഉൾപ്പെട്ടിരിക്കുന്നു?',
      'sos_chip_cat_accident': 'അപകടം',
      'sos_chip_cat_medical': 'വൈദ്യം',
      'sos_chip_cat_hazard': 'അപായം (തീ, മുങ്ങൽ മുതലായവ)',
      'sos_chip_cat_assault': 'ആക്രമണം',
      'sos_chip_cat_other': 'മറ്റുള്ളവ',
      'sos_chip_safe_critical': 'ഗുരുതരം (ജീവന് ഭീഷണി)',
      'sos_chip_safe_injured': 'പരിക്ക്; സ്ഥിരം',
      'sos_chip_safe_danger': 'പരിക്കില്ല; അപായത്തിൽ',
      'sos_chip_safe_safe_now': 'ഇപ്പോൾ സുരക്ഷിതം',
      'sos_chip_people_me': 'ഞാൻ മാത്രം',
      'sos_chip_people_two': 'ഇരുവർ',
      'sos_chip_people_many': 'ഇരുവരിൽ കൂടുതൽ',
      'sos_tts_interview_saved':
          'ബാധിത ഇന്റർവ്യൂ ഡാറ്റ സേവ് ചെയ്തു. പ്രതികരിക്കുന്നവർക്ക് വിശദാംശങ്ങൾ ഉണ്ട്.',
      'sos_tts_map_routes':
          'മാപ്പ് ടാബ് തുറക്കുക: ചുവപ്പ് നിയോഗിച്ച ആശുപത്രിയിലേക്ക് റോഡ് മാർഗ്ഗം അല്ലെങ്കിൽ സമീപ മാർഗ്ഗം; പച്ച സ്വയംസേവക മാർഗ്ഗം. അടിയന്തര വോയ്സ് ചാനലിൽ തുടരുക.',
      'sos_tts_emergency_contacts_on_file':
          'Your emergency contact from your profile is attached to this SOS. SMS updates may be sent when that option is enabled.',
      'sos_tts_conscious_no_answer_attempt':
          'മറുപടിയില്ല. ബോധ പരിശോധന {max}ൽ {n}. ഒരു മിനിറ്റിന് ശേഷം വീണ്ടും ചോദിക്കും.',
      'voice_volunteer_accepted':
          'സ്വയംസേവകൻ സ്വീകരിച്ചു. സഹായം വരുന്നു.',
      'voice_ambulance_dispatched_eta':
          'ആംബുലൻസ് അയച്ചു. പ്രതീക്ഷിത വരവ്: {eta}.',
      'voice_police_dispatched_eta':
          'പോലീസ് അയച്ചു. പ്രതീക്ഷിത വരവ്: {eta}.',
      'voice_ambulance_on_scene_victim':
          'ആംബുലൻസ് സ്ഥലത്താണ് — നിങ്ങളിൽ നിന്ന് ഏകദേശം ഇരുനൂറ് മീറ്റർ അകലെ.',
      'voice_ambulance_on_scene_volunteer':
          'ആംബുലൻസ് സ്ഥലത്താണ് — സംഭവസ്ഥലത്തിൽ നിന്ന് ഏകദേശം ഇരുനൂറ് മീറ്ററിനുള്ളിൽ.',
      'voice_ambulance_returning': 'ആംബുലൻസ് ആശുപത്രിയിലേക്ക് മടങ്ങുന്നു.',
      'voice_response_complete_station':
          'പ്രതികരണം പൂർത്തിയായി. ആംബുലൻസ് സ്റ്റേഷനിൽ.',
      'voice_response_complete_cycle':
          'പ്രതികരണം പൂർത്തിയായി. ആംബുലൻസ് സ്റ്റേഷനിൽ. മൊത്തം ചക്രം {minutes} മിനിറ്റ് {seconds} സെക്കൻഡ്.',
      'voice_volunteers_on_scene_count':
          '{n} സ്വയംസേവകർ ഇപ്പോൾ സ്ഥലത്തുണ്ട്.',
      'voice_one_volunteer_on_scene': 'ഒരു സ്വയംസേവകൻ സ്ഥലത്തുണ്ട്.',
      'voice_ptt_joined_comms': '{who} വോയ്സ് കമ്മ്യൂണിക്കേഷനിൽ ചേർന്നു.',
      'voice_tts_unavailable_banner':
          'വോയ്സ് മാർഗനിർദ്ദേശം ലഭ്യമല്ല — സ്ക്രീനിലെ വാചകം വായിക്കുക.',
      'language_picker_title': 'ഭാഷ',
      'volunteer_victim_medical_card': 'ബാധിത മെഡിക്കൽ കാർഡ്',
      'volunteer_dispatch_milestone_title': 'ഡിസ്പാച്ച് അപ്‌ഡേറ്റുകൾ',
      'volunteer_dispatch_milestone_hospital': 'ആശുപത്രി സ്വീകരിച്ചു: {hospital}',
      'volunteer_dispatch_milestone_unit': 'ആംബുലൻസ് യൂണിറ്റ്: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'ആംബുലൻസ് ക്രൂ: ഏകോപനം…',
      'volunteer_dispatch_milestone_en_route': 'ആംബുലൻസ് വഴിയിൽ',
      'volunteer_triage_qr_report_title': 'QR അല്ലെങ്കിൽ ടാപ്പ് റിപ്പോർട്ട്',
      'volunteer_triage_qr_report_subtitle':
          'ഹാൻഡ്‌ഓഫിനായി കോഡ് സ്കാൻ ചെയ്യുക അല്ലെങ്കിൽ സംഭവ റിപ്പോർട്ട് സേവ് ചെയ്യാൻ ടാപ്പ് ചെയ്യുക.',
      'volunteer_triage_show_qr': 'QR കാണിക്കുക',
      'volunteer_triage_tap_report': 'റിപ്പോർട്ട്',
      'volunteer_triage_qr_title': 'സംഭവ ഹാൻഡ്‌ഓഫ് QR',
      'volunteer_triage_qr_body': 'ഘടനാപരമായ ഡാറ്റിനായി സ്റ്റാഫ് അല്ലെങ്കിൽ EMS ഉടൻ പങ്കിടുക.',
      'volunteer_triage_report_saved': 'റിപ്പോർട്ട് ഈ സംഭവത്തിന് കീഴിൽ സേവ് ചെയ്തു.',
      'volunteer_triage_report_failed': 'റിപ്പോർട്ട് സേവ് ചെയ്യാൻ കഴിഞ്ഞില്ല: ',
      'volunteer_victim_medical_offline_hint': 'SOS പാക്കറ്റിൽ നിന്ന് — ഓഫ്‌ലൈനിൽ കാഷിൽ.',
      'volunteer_victim_consciousness_title': 'ബോധം',
      'volunteer_victim_three_questions': 'ആദ്യ മറുപടികൾ',
      'volunteer_major_updates_log': 'പ്രധാന അപ്‌ഡേറ്റുകൾ മാത്രം',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'ടിയർ {tier} വരെ ഉയർത്തുന്നു. ആശുപത്രി {hospital} ശ്രമിക്കുന്നു.',
      'volunteer_dispatch_trying_hospital': 'ആശുപത്രി {hospital} ശ്രമിക്കുന്നു.',
      'volunteer_dispatch_hospital_accepted':
          '{hospital} അടിയന്തരം സ്വീകരിച്ചു. ആംബുലൻസ് ഏകോപനം നടക്കുന്നു.',
      'volunteer_dispatch_all_hospitals_notified':
          'എല്ലാ ആശുപത്രികളെയും അറിയിച്ചു. അടിയന്തര സേവനങ്ങളിലേക്ക് ഉയർത്തുന്നു.',
      'sos_dispatch_alerting_nearest_trying':
          'നിങ്ങളുടെ പ്രദേശത്തെ അടുത്തുള്ള ആശുപത്രിയെ അലേർട്ട് ചെയ്യുന്നു. {hospital} ശ്രമിക്കുന്നു.',
      'sos_dispatch_escalating_tier_trying':
          'പ്രതികരണമില്ല. ടിയർ {tier} വരെ ഉയർത്തുന്നു. {hospital} ശ്രമിക്കുന്നു.',
      'sos_dispatch_retry_previous_trying':
          'മുമ്പത്തെ ആശുപത്രിയിൽ നിന്ന് പ്രതികരണമില്ല. {hospital} ശ്രമിക്കുന്നു.',
      'sos_dispatch_all_hospitals_call_112':
          'എല്ലാ ആശുപത്രികളെയും അറിയിച്ചു. അടിയന്തര സേവനങ്ങൾക്ക് ദയവായി 112 വിളിക്കുക.',
      'sos_active_title_big': 'സജീവ SOS',
      'sos_active_help_coming': 'സഹായം വരുന്നു. ശാന്തമായിരിക്കുക.',
      'sos_active_badge_waiting': 'കാത്തിരിക്കുന്നു',
      'sos_active_badge_en_route_count': '{n} വഴിയിൽ',
      'sos_active_mini_ambulance': 'ആംബുലൻസ്',
      'sos_active_mini_on_scene': 'സ്ഥലത്ത്',
      'sos_active_mini_status': 'സ്ഥിതി',
      'sos_active_volunteers_count_short': '{n} വോളണ്ടിയർമാർ',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title':
          'എല്ലാ ആശുപത്രികളെയും അറിയിച്ചു',
      'sos_active_all_hospitals_notified_subtitle':
          'സമയത്ത് ഒരു ആശുപത്രിയും സ്വീകരിച്ചില്ല. ഡിസ്പാച്ച് അടിയന്തര സേവനങ്ങളിലേക്ക് എസ്കലേറ്റ് ചെയ്യുന്നു.',
      'sos_active_position_refresh_note':
          'ബാറ്ററി ലാഭിക്കാൻ SOS സമയത്ത് നിങ്ങളുടെ സ്ഥാനം ഏകദേശം 45 സെക്കൻഡിൽ ഒരിക്കൽ പുതുക്കുന്നു. ആപ്പ് തുറന്നിടുക, കഴിയുമെങ്കിൽ ചാർജിൽ ഇടുക.',
      'sos_active_mic_active': 'മൈക്ക് · സജീവം',
      'sos_active_mic_active_detail':
          'ലൈവ് ചാനൽ നിങ്ങളുടെ മൈക്രോഫോൺ സ്വീകരിക്കുന്നു.',
      'sos_active_mic_standby': 'മൈക്ക് · സ്റ്റാൻഡ്‌ബൈ',
      'sos_active_mic_standby_detail': 'വോയ്സ് ചാനലിനായി കാത്തിരിക്കുന്നു…',
      'sos_active_mic_connecting': 'മൈക്ക് · കണക്റ്റുചെയ്യുന്നു',
      'sos_active_mic_connecting_detail':
          'അടിയന്തര വോയ്സ് ചാനലിൽ ചേരുന്നു…',
      'sos_active_mic_reconnecting': 'മൈക്ക് · വീണ്ടും കണക്റ്റ്',
      'sos_active_mic_reconnecting_detail':
          'ലൈവ് ഓഡിയോ പുനഃസ്ഥാപിക്കുന്നു…',
      'sos_active_mic_failed': 'മൈക്ക് · തടസ്സം',
      'sos_active_mic_failed_detail':
          'വോയ്സ് ചാനൽ ലഭ്യമല്ല. മുകളിൽ RETRY ഉപയോഗിക്കുക.',
      'sos_active_mic_ptt_only': 'മൈക്ക് · സംഭവ ചാനൽ',
      'sos_active_mic_ptt_only_detail':
          'ഓപ്പറേഷൻസ് കൺസോൾ Firebase PTT വഴി വോയ്സ് റൂട്ട് ചെയ്തു. പ്രതികരിക്കുന്നവരെ ബന്ധപ്പെടാൻ ബ്രോഡ്കാസ്റ്റ് അമർത്തിപ്പിടിക്കുക.',
      'sos_active_mic_interrupted': 'മൈക്ക് · തടസ്സപ്പെട്ടു',
      'sos_active_mic_interrupted_detail':
          'ആപ്പ് ഓഡിയോ പ്രോസസ് ചെയ്യുമ്പോൾ ചെറിയ ഇടവേള.',
      'sos_active_consciousness_note':
          'ബോധപരിശോധനയ്ക്ക് അതെ അല്ലെങ്കിൽ ഇല്ല എന്ന് മറുപടി നൽകുക; മറ്റ് സൂചനകൾ സ്ക്രീൻ ഓപ്ഷനുകൾ ഉപയോഗിക്കുന്നു.',
      'sos_active_live_updates_header': 'ലൈവ് അപ്‌ഡേറ്റുകൾ',
      'sos_active_live_updates_subtitle':
          'ഡിസ്പാച്ച്, വോളണ്ടിയർമാർ & ഉപകരണം',
      'sos_active_live_tag': 'ലൈവ്',
      'sos_active_activity_log': 'പ്രവർത്തന ലോഗ്',
      'sos_active_header_stat_coordinating_crew': 'ജീവനക്കാരുടെ ഏകോപനം',
      'sos_active_header_stat_coordinating': 'ഏകോപനം',
      'sos_active_header_stat_en_route': 'വഴിയിൽ',
      'sos_active_header_stat_route_min': '~{n} മിനിറ്റ്',
      'sos_active_live_sos_is_live_title': 'SOS ലൈവാണ്',
      'sos_active_live_sos_is_live_detail':
          'നിങ്ങളുടെ സ്ഥാനവും മെഡിക്കൽ ഫ്ലാഗുകളും അടിയന്തര നെറ്റ്‌വർക്കിൽ ഉണ്ട്.',
      'sos_active_live_volunteers_notified_title':
          'വോളണ്ടിയർമാരെ അറിയിച്ചു',
      'sos_active_live_volunteers_notified_detail':
          'അടുത്തുള്ള വോളണ്ടിയർമാർക്ക് ഈ സംഭവം തത്സമയം ലഭിക്കുന്നു.',
      'sos_active_live_bridge_connected_title':
          'അടിയന്തര വോയ്സ് ബ്രിഡ്ജ് ബന്ധിപ്പിച്ചു',
      'sos_active_live_bridge_connected_detail':
          'ഡിസ്പാച്ച് ഡെസ്കും പ്രതികരിക്കുന്നവരും ഈ ചാനൽ കേൾക്കാനാകും.',
      'sos_active_live_ptt_title': 'Firebase PTT വഴി വോയ്സ്',
      'sos_active_live_ptt_detail':
          'ഈ ഫ്ലീറ്റിനായി ലൈവ് WebRTC ബ്രിഡ്ജ് ഓഫാണ്. വോയ്സ്, ടെക്സ്റ്റ് അപ്ഡേറ്റുകൾക്ക് ബ്രോഡ്കാസ്റ്റ് ഉപയോഗിക്കുക.',
      'sos_active_live_contacts_notified_title':
          'അടിയന്തര കോൺടാക്റ്റുകളെ അറിയിച്ചു',
      'sos_active_live_hospital_accepted_title': 'ആശുപത്രി സ്വീകരിച്ചു',
      'sos_active_live_ambulance_unit_assigned_title':
          'ആംബുലൻസ് യൂണിറ്റ് നിയോഗിച്ചു',
      'sos_active_live_ambulance_unit_assigned_subtitle': 'യൂണിറ്റ് {unit}',
      'sos_active_live_ambulance_en_route_title': 'ആംബുലൻസ് വഴിയിൽ',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'വഴിയിൽ',
      'sos_active_live_ambulance_en_route_route_eta': '~{n} മിനി (റൂട്ട്)',
      'sos_active_live_ambulance_coordination_title': 'ആംബുലൻസ് ഏകോപനം',
      'sos_active_live_ambulance_coordination_pending':
          'ആശുപത്രി സ്വീകരിച്ചു — ആംബുലൻസ് ഓപ്പറേറ്റർമാരെ അറിയിക്കുന്നു.',
      'sos_active_live_ambulance_coordination_arranging':
          'ആംബുലൻസ് ക്രൂ ക്രമീകരണം — യൂണിറ്റ് വഴിയിലായാൽ മിനിറ്റ് ETA.',
      'sos_active_live_responder_status_title': 'പ്രതികരണക്കാരന്റെ സ്ഥിതി',
      'sos_active_live_volunteer_accepted_single_title':
          'വോളണ്ടിയർ സ്വീകരിച്ചു',
      'sos_active_live_volunteer_accepted_many_title':
          'വോളണ്ടിയർമാർ സ്വീകരിച്ചു',
      'sos_active_live_volunteer_accepted_single_detail':
          'ഒരു പ്രതികരണക്കാരൻ നിയോഗിക്കപ്പെട്ട് നിങ്ങളെ സഹായിക്കാൻ വരുന്നു.',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} പ്രതികരണക്കാർ ഈ SOS-ന് നിയോഗിക്കപ്പെട്ടു.',
      'sos_active_live_volunteer_on_scene_single_title':
          'വോളണ്ടിയർ സ്ഥലത്തെത്തി',
      'sos_active_live_volunteer_on_scene_many_title':
          'വോളണ്ടിയർമാർ സ്ഥലത്ത്',
      'sos_active_live_volunteer_on_scene_single_detail':
          'ആരെങ്കിലും നിങ്ങളോടൊപ്പം അല്ലെങ്കിൽ നിങ്ങളുടെ പിന്നിലാണ്.',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} പ്രതികരണക്കാർ സ്ഥലത്ത് അടയാളപ്പെടുത്തി.',
      'sos_active_live_responder_location_title':
          'ലൈവ് പ്രതികരണക്കാരന്റെ സ്ഥാനം',
      'sos_active_live_responder_location_detail':
          'നിയോഗിച്ച വോളണ്ടിയറുടെ GPS മാപ്പിൽ അപ്‌ഡേറ്റുചെയ്യുന്നു.',
      'sos_active_live_professional_dispatch_title':
          'പ്രൊഫഷണൽ ഡിസ്പാച്ച് സജീവം',
      'sos_active_live_professional_dispatch_detail':
          'ഏകോപിത സേവനങ്ങൾ ഈ സംഭവത്തിൽ പ്രവർത്തിക്കുന്നു.',
      'sos_active_ambulance_200m_detail':
          'ആംബുലൻസ് സ്ഥലത്ത് — ഏകദേശം 200 മീറ്ററിനുള്ളിൽ.',
      'sos_active_ambulance_200m_semantic_label':
          'ആംബുലൻസ് ഏകദേശം ഇരുനൂറ് മീറ്ററിനുള്ളിൽ സ്ഥലത്ത്',
      'sos_active_bridge_channel_on_suffix': ' · {n} ചാനലിൽ',
      'sos_active_bridge_channel_voice': 'അടിയന്തര വോയ്സ് ചാനൽ',
      'sos_active_bridge_channel_ptt': 'അടിയന്തര ചാനൽ · Firebase PTT',
      'sos_active_bridge_channel_failed': 'അടിയന്തര ചാനൽ · വീണ്ടും ശ്രമിക്കുക',
      'sos_active_bridge_channel_connecting':
          'അടിയന്തര ചാനൽ · കണക്റ്റുചെയ്യുന്നു',
      'sos_active_dispatch_contact_hospitals_default':
          'നിങ്ങളുടെ സ്ഥാനത്തിനും അടിയന്തര തരത്തിനും അനുസരിച്ച് അടുത്തുള്ള ആശുപത്രികളെ ബന്ധപ്പെടുന്നു.',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'ആംബുലൻസ് ക്രൂവിനെ അറിയിച്ചു',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'പങ്കാളി ആശുപത്രി നിങ്ങളുടെ കേസ് സ്വീകരിച്ചു. ആംബുലൻസ് ഓപ്പറേറ്റർമാരെ അറിയിക്കുന്നു.',
      'sos_active_dispatch_ambulance_confirmed_title':
          'ആംബുലൻസ് സ്ഥിരീകരിച്ചു',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'യൂണിറ്റ് {unit} നിങ്ങളുടെ അടുത്തേക്ക് വരുന്നു. പ്രതികരണക്കാർക്ക് എത്താൻ കഴിയുന്നിടത്ത് തുടരുക.',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'ഒരു ആംബുലൻസ് നിങ്ങളുടെ അടുത്തേക്ക് വരുന്നു. പ്രതികരണക്കാർക്ക് എത്താൻ കഴിയുന്നിടത്ത് തുടരുക.',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'ആംബുലൻസ് കൈമാറ്റം വൈകി',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'ആശുപത്രി സ്വീകരിച്ചു, പക്ഷേ സമയത്ത് ആംബുലൻസ് ക്രൂ സ്ഥിരീകരിച്ചില്ല. ഡിസ്പാച്ച് എസ്കലേറ്റ് ചെയ്യുന്നു — ആവശ്യമെങ്കിൽ 112 ൽ വിളിക്കുക.',
      'sos_active_dispatch_pending_title_trying': 'ശ്രമം: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · ആശുപത്രി പ്രതികരണത്തിനായി കാത്തിരിക്കുന്നു.',
      'sos_active_dispatch_accepted_title': '{hospital} സ്വീകരിച്ചു',
      'sos_active_dispatch_accepted_subtitle':
          'ആംബുലൻസ് ഡിസ്പാച്ച് ഏകോപിപ്പിക്കുന്നു.',
      'sos_active_dispatch_exhausted_title':
          'എല്ലാ ആശുപത്രികളെയും അറിയിച്ചു',
      'sos_active_dispatch_exhausted_subtitle':
          'സമയത്ത് ഒരു ആശുപത്രിയും സ്വീകരിച്ചില്ല. ഡിസ്പാച്ച് അടിയന്തര സേവനങ്ങളിലേക്ക് എസ്കലേറ്റ് ചെയ്യുന്നു.',
      'sos_active_dispatch_generic_title': 'ആശുപത്രി ഡിസ്പാച്ച്',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'അടിയന്തര വോയ്സ് ചാനൽ',
      'volunteer_bridge_join_hint_incident':
          'ചേരൽ ഈ സംഭവം ഉപയോഗിക്കുന്നു: നിങ്ങളുടെ നമ്പർ പൊരുത്തപ്പെട്ടാൽ അടിയന്തര കോൺടാക്റ്റ്; അല്ലെങ്കിൽ സ്വീകരിച്ച വോളണ്ടിയർ.',
      'volunteer_bridge_join_hint_elite':
          'നിങ്ങൾ സ്വീകരിച്ച പ്രതികരണക്കാരനായിരിക്കുമ്പോൾ ചേരൽ നിങ്ങളുടെ എലൈറ്റ് വോളണ്ടിയർ ആക്സസ് ഉപയോഗിക്കുന്നു; അല്ലെങ്കിൽ നിങ്ങളുടെ നമ്പർ പൊരുത്തപ്പെട്ടാൽ കോൺടാക്റ്റ്.',
      'volunteer_bridge_join_hint_desk':
          'നിങ്ങളുടെ പ്രൊഫൈലിലെ അടിയന്തര സേവന ഡെസ്കായി നിങ്ങൾ ഡിസ്പാച്ചായി ചേരുന്നു.',
      'volunteer_bridge_join_voice_btn': 'വോയ്സിൽ ചേരുക',
      'volunteer_bridge_connecting_btn': 'കണക്റ്റുചെയ്യുന്നു…',
      'volunteer_bridge_incident_id_hint': 'സംഭവം ID',
      'volunteer_consignment_live_location_hint':
          'നിങ്ങൾ കൺസൈൻമെന്റിലായിരിക്കുമ്പോൾ, മാപ്പും ETA-യും കൃത്യമായി തുടരാൻ നിങ്ങളുടെ ലൈവ് സ്ഥാനം ഈ സംഭവവുമായി പങ്കിടുന്നു.',
      'volunteer_consignment_low_power_label': 'ലോ പവർ',
      'volunteer_consignment_normal_gps_label': 'സാധാരണ GPS',
      'bridge_card_incident_id_missing': 'സംഭവ ID ഇല്ല.',
      'bridge_card_ptt_only_snackbar':
          'ഓപ്പറേഷൻ കൺസോൾ ഇരയുടെ ശബ്ദം Firebase PTT വഴി അയച്ചു. WebRTC ബ്രിഡ്ജ് ചേരൽ പ്രവർത്തനരഹിതം.',
      'bridge_card_ptt_only_banner':
          'കൺസോൾ Firebase PTT വഴി ശബ്ദം അയച്ചു — ഈ ഫ്ലീറ്റിനായി LiveKit ബ്രിഡ്ജ് ചേരൽ പ്രവർത്തനരഹിതം.',
      'bridge_card_connected_snackbar': 'വോയ്‌സ് ചാനലുമായി ബന്ധിപ്പിച്ചു.',
      'bridge_card_could_not_join': 'ചേരാൻ കഴിഞ്ഞില്ല: {err}',
      'bridge_card_voice_channel_title': 'വോയ്‌സ് ചാനൽ',
      'bridge_card_calm_disclaimer':
          'ശാന്തത പാലിക്കുക, വ്യക്തമായി സംസാരിക്കുക. സ്ഥിരമായ ശബ്ദം ഇരയ്ക്കും മറ്റ് സഹായികൾക്കും ഉപകരിക്കും. ശബ്ദമുയർത്തുകയോ വാക്കുകൾ വേഗത്തിൽ പറയുകയോ ചെയ്യരുത്.',
      'bridge_card_cancel': 'റദ്ദാക്കുക',
      'bridge_card_join_voice': 'വോയ്‌സിൽ ചേരുക',
      'bridge_card_voice_connected': 'വോയ്‌സ് ബന്ധിപ്പിച്ചു',
      'bridge_card_in_channel': 'ചാനലിൽ {n} പേർ',
      'bridge_card_transmitting': 'സംപ്രേഷണം ചെയ്യുന്നു…',
      'bridge_card_hold_to_talk': 'സംസാരിക്കാൻ അമർത്തിപ്പിടിക്കുക',
      'bridge_card_disconnect': 'വിച്ഛേദിക്കുക',
      'vol_ems_banner_en_route': 'ആംബുലൻസ് സംഭവസ്ഥലത്തേക്ക് പോകുന്നു',
      'vol_ems_banner_on_scene': 'ആംബുലൻസ് സ്ഥലത്ത് (~200 മീ)',
      'vol_ems_banner_returning': 'ആംബുലൻസ് ആശുപത്രിയിലേക്ക് മടങ്ങുന്നു',
      'vol_ems_banner_complete': 'പ്രതികരണം പൂർണം · ആംബുലൻസ് സ്റ്റേഷനിൽ',
      'vol_ems_banner_complete_with_cycle':
          'പ്രതികരണം പൂർണം · ആംബുലൻസ് സ്റ്റേഷനിൽ · മൊത്തം സൈക്കിൾ {m}മി {s}സെ',
      'vol_tooltip_lifeline_first_aid':
          'ലൈഫ്‌ലൈൻ — പ്രാഥമിക ചികിത്സാ ഗൈഡുകൾ (പ്രതികരണത്തിൽ തുടരും)',
      'vol_tooltip_exit_mission': 'മിഷൻ നിർത്തുക',
      'vol_low_power_tracking_hint':
          'ലോ-പവർ ട്രാക്കിംഗ്: നിങ്ങളുടെ സ്ഥാനം കുറവ് തവണ, വലിയ ചലനങ്ങൾക്ക് ശേഷം മാത്രം സിങ്ക് ചെയ്യും. ഡിസ്പാച്ച് നിങ്ങളുടെ അവസാന പോയിന്റ് കാണും.',
      'vol_marker_you': 'നിങ്ങൾ',
      'vol_marker_active_unit': 'സജീവ യൂണിറ്റ്',
      'vol_marker_practice_incident': 'അഭ്യാസ സംഭവം',
      'vol_marker_accident_scene': 'അപകട സ്ഥലം',
      'vol_marker_training_pin': 'പരിശീലന പിൻ — യഥാർത്ഥ SOS അല്ല',
      'vol_marker_high_severity': 'GITM കോളേജ് - ഉയർന്ന തീവ്രത',
      'vol_marker_accepted_hospital': 'സ്വീകരിച്ചു: {hospital}',
      'vol_marker_trying_hospital': 'ശ്രമം: {hospital}',
      'vol_marker_ambulance_on_scene': 'ആംബുലൻസ് സ്ഥലത്ത്!',
      'vol_marker_ambulance_en_route': 'ആംബുലൻസ് വഴിയിൽ',
      'vol_badge_at_scene_pin': 'സ്ഥല പിന്നിൽ',
      'vol_badge_in_5km_zone': '5 കിമീ സോണിൽ',
      'vol_badge_en_route': 'വഴിയിൽ',
    },

    // ── Bengali (বাংলা) ────────────────────────────────────────────────────
    'bn': {
      'app_name': 'EmergencyOS',
      'profile_title': 'প্রোফাইল ও মেডিক্যাল আইডি',
      'language': 'ভাষা',
      'save_medical_profile': 'মেডিক্যাল প্রোফাইল সংরক্ষণ করুন',
      'critical_medical_info': 'গুরুত্বপূর্ণ চিকিৎসা তথ্য',
      'emergency_contacts': 'জরুরি যোগাযোগ',
      'golden_hour_details': 'গোল্ডেন আওয়ার বিবরণ',
      'sos_lock': 'SOS লক',
      'top_life_savers': 'শীর্ষ জীবন রক্ষাকারী',
      'lives_saved': 'উদ্ধারকৃত প্রাণ',
      'active_alerts': 'সক্রিয় সতর্কতা',
      'rank': 'র‍্যাঙ্ক',
      'on_duty': 'ডিউটিতে',
      'standby': 'স্ট্যান্ডবাই',
      'sos': 'SOS',
      'call_now': 'এখনই কল করুন',
      'quick_guide': 'দ্রুত গাইড',
      'detailed_instructions': 'বিস্তারিত নির্দেশনা',
      'red_flags': 'বিপদ সংকেত',
      'cautions': 'সতর্কতা',
      'voice_walkthrough': 'ভয়েস গাইড',
      'playing': 'চলছে...',
      'swipe_next_guide': 'পরবর্তী গাইডের জন্য সোয়াইপ করুন',
      'watch_video_guide': 'সম্পূর্ণ ভিডিও গাইড দেখুন',
      'emergency_grid_scan': 'জরুরি গ্রিড স্ক্যান',
      'area_telemetry': 'এলাকা টেলিমেট্রি ও ঝুঁকি সূচক',
      'report_hazard': 'বিপদ রিপোর্ট করুন',
      'todays_duty': 'আজকের দায়িত্ব',
      'blood_type': 'রক্তের গ্রুপ',
      'allergies': 'অ্যালার্জি',
      'medical_conditions': 'চিকিৎসা অবস্থা',
      'contact_name': 'প্রাথমিক যোগাযোগের নাম',
      'contact_phone': 'প্রাথমিক যোগাযোগ ফোন',
      'relationship': 'সম্পর্ক',
      'medications': 'বর্তমান ওষুধ',
      'organ_donor': 'অঙ্গ দাতা স্থিতি',
      'good_morning': 'সুপ্রভাত,',
      'good_afternoon': 'শুভ অপরাহ্ন,',
      'good_evening': 'শুভ সন্ধ্যা,',
      'hospitals': 'হাসপাতাল',
      'visual_walkthrough': 'ভিজ্যুয়াল গাইড',
      'lifeline': 'লাইফলাইন',
      'nav_home': 'হোম',
      'nav_map': 'ম্যাপ',
      'nav_grid': 'গ্রিড',
      'nav_profile': 'প্রোফাইল',
      'map_caching_offline_pct': 'অফলাইনের জন্য এলাকা ক্যাশ হচ্ছে — {pct}%',
      'map_drill_practice_banner':
          'অনুশীলন গ্রিড: পালসিং পিন = ডেমো সক্রিয় সতর্কতা। স্তরের জন্য মানচিত্র ফিল্টার — আসল ডেটা নয়।',
      'map_recenter_tooltip': 'আবার কেন্দ্রে আনুন',
      'map_legend_hospital': 'হাসপাতাল',
      'map_legend_live_sos_history': 'লাইভ SOS / ইতিহাস',
      'map_legend_past_this_hex': 'অতীত (এই হেক্স)',
      'map_legend_in_area': 'এলাকায় {n}',
      'map_legend_in_cell': 'সেলে {n}',
      'map_legend_volunteers_on_duty': 'ডিউটিতে স্বেচ্ছাসেবক',
      'map_legend_volunteers_in_grid': 'গ্রিডে {n}',
      'map_legend_responder_scene': 'প্রতিকারকারী → দৃশ্য',
      'map_responder_routes_one': '{n} রুট',
      'map_responder_routes_many': '{n} রুট',
      'map_filters_title': 'মানচিত্র ফিল্টার',
      'step_prefix': 'ধাপ',
      'highlights_steps': 'একটি একটি করে ধাপ দেখায়',
      'offline_mode': 'অফলাইন — নেটওয়ার্ক বিচ্ছিন্ন',
      'volunteer': 'স্বেচ্ছাসেবক',
      'unranked': 'র‍্যাঙ্কবিহীন',
      'live': 'লাইভ',
      'you': 'আপনি',
      'saved': 'বাঁচানো',
      'xp_responses': 'XP · {0} প্রতিক্রিয়া',
      'duty_monitoring': 'আপনি ডিউটিতে থাকাকালীন SOS পপ-আপ চালু আছে।',
      'turn_on_duty_msg': 'SOS পপ-আপ পেতে ডিউটি চালু করুন।',
      'on_duty_snack': 'ডিউটিতে — আপনার এলাকায় ঘটনা পর্যবেক্ষণ করা হচ্ছে...',
      'off_duty_snack': 'স্ট্যান্ডবাই — ডিউটি সেশন রেকর্ড হয়েছে।',
      'leaderboard_offline': 'লিডারবোর্ড অফলাইন',
      'leaderboard_offline_sub': 'সিংক বিরত। ক্যাশ স্কোর দেখানো হচ্ছে।',
      'set_sos_pin_first': 'প্রথমে SOS পিন সেট করুন',
      'set_pin_safety_msg': 'নিরাপত্তার জন্য, SOS তৈরি করার আগে পিন সেট করতে হবে।',
      'set_pin_now': 'এখনই পিন সেট করুন',
      'later': 'পরে',
      'sos_screen_title': 'SOS',
      'sos_hold_banner': 'পাঠাতে ৩ সেকেন্ড ধরে চেপে ধরুন।',
      'sos_hold_button': 'SOS পাঠাতে চেপে ধরুন',
      'sos_semantics_hold_hint': 'SOS। পাঠাতে তিন সেকেন্ড চেপে ধরুন।',
      'home_duty_heading': 'আজকের দায়িত্ব',
      'home_duty_progress': '{done}/{total} সম্পন্ন',
      'home_map_semantics': 'আপনার এলাকা ও অবস্থান দেখানো মানচিত্র',
      'home_recenter_map': 'মানচিত্র আপনার অবস্থানে কেন্দ্র করুন',
      'home_sos_large_fab_hint': 'জরুরি সতর্কতার জন্য SOS কাউন্টডাউন খুলুন',
      'home_sos_cancelled_snack': 'SOS বাতিল।',
      'home_sos_sent_snack': 'SOS পাঠানো হয়েছে! জরুরি সেবা অবহিত।',
      'quick_sos_title': 'দ্রুত SOS',
      'quick_sos_subtitle': 'উত্তর দিন — বিবরণ দিলে সাহায্য দ্রুত আসে',
      'quick_sos_practice_banner':
          'অনুশীলন গাইডেড ইনটেক — জমা দিলে আসল SOS হবে না।',
      'quick_sos_section_what': 'জরুরি কী?',
      'quick_sos_section_someone_else': 'আপনি কি অন্যের জন্য SOS চালু করছেন?',
      'quick_sos_send_now': 'এখনই SOS পাঠান',
      'quick_sos_select_first': 'জরুরি নির্বাচন করুন ও নিশ্চিত করুন',
      'quick_sos_section_victim': 'কর্তৃগত অবস্থা',
      'quick_sos_victim_subtitle': 'উদ্ধারকারীদের সঠিক সরঞ্জাম প্রস্তুত করতে সাহায্য করে',
      'quick_sos_section_people': 'কতজনের সাহায্য দরকার?',
      'quick_sos_yes_someone_else': 'হ্যাঁ — অন্যের জন্য',
      'quick_sos_no_for_me': 'না — আমার জন্য',
      'quick_sos_other_hint': 'সংক্ষেপে আপনার পরিস্থিতি বর্ণনা করুন...',
      'quick_sos_close': 'দ্রুত SOS বন্ধ করুন',
      'quick_sos_drill_submit_disabled':
          'অনুশীলন: জমা নিষ্ক্রিয়। ড্রিলের জন্য হোমে লাল SOS ৩ সে. চেপে ধরুন।',
      'quick_sos_failed': 'SOS ব্যর্থ: {detail}',
      'quick_sos_could_not_start': 'SOS শুরু করা যায়নি। আবার চেষ্টা করুন।',
      'quick_sos_victim_conscious_q': 'ব্যক্তি সচেতন?',
      'sos_are_you_conscious':
          'আপনি সচেতন? দয়া করে হ্যাঁ বা না উত্তর দিন।',
      'sos_tts_opening_guidance':
          'আপনার SOS সক্রিয়। সাহায্য আসছে। বলা নির্দেশাবলী অনুসরণ করুন এবং উত্তর দিতে ট্যাপ করুন।',
      'sos_interview_q1_prompt': 'কী হচ্ছে? (জরুরি ধরন)',
      'sos_interview_q2_prompt': 'আপনি কি নিরাপদ? কতটা গুরুতর?',
      'sos_interview_q3_prompt': 'কতজন জড়িত?',
      'sos_chip_cat_accident': 'দুর্ঘটনা',
      'sos_chip_cat_medical': 'চিকিৎসা',
      'sos_chip_cat_hazard': 'বিপদ (আগুন, ডুবি ইত্যাদি)',
      'sos_chip_cat_assault': 'আক্রমণ',
      'sos_chip_cat_other': 'অন্যান্য',
      'sos_chip_safe_critical': 'গুরুতর (জীবনঘাতী)',
      'sos_chip_safe_injured': 'আহত কিন্তু স্থিতিশীল',
      'sos_chip_safe_danger': 'আহত নয় কিন্তু বিপদে',
      'sos_chip_safe_safe_now': 'এখন নিরাপদ',
      'sos_chip_people_me': 'শুধু আমি',
      'sos_chip_people_two': 'দুজন',
      'sos_chip_people_many': 'দুজনের বেশি',
      'sos_tts_interview_saved':
          'সব ভুক্তভোগী সাক্ষাৎকার ডেটা সংরক্ষিত। উদ্ধারকারীদের বিস্তারিত আছে।',
      'sos_tts_map_routes':
          'মানচিত্র ট্যাব খুলুন: লাল নির্ধারিত হাসপাতালের রাস্তার পথ, নাহলে সংক্ষিপ্ত পথ; সবুজ স্বেচ্ছাসেবক পথ। জরুরি ভয়েস চ্যানেলে থাকুন।',
      'sos_tts_emergency_contacts_on_file':
          'Your emergency contact from your profile is attached to this SOS. SMS updates may be sent when that option is enabled.',
      'sos_tts_conscious_no_answer_attempt':
          'উত্তর নেই। সচেতনতা পরীক্ষা {max} এর {n}। এক মিনিট পর আবার জিজ্ঞাসা করব।',
      'voice_volunteer_accepted':
          'স্বেচ্ছাসেবক গ্রহণ করেছে। সাহায্য পথে আছে।',
      'voice_ambulance_dispatched_eta':
          'অ্যাম্বুলেন্স পাঠানো হয়েছে। আনুমানিক আগমন: {eta}।',
      'voice_police_dispatched_eta':
          'পুলিশ পাঠানো হয়েছে। আনুমানিক আগমন: {eta}।',
      'voice_ambulance_on_scene_victim':
          'অ্যাম্বুলেন্স ঘটনাস্থলে — আপনার থেকে প্রায় দুইশো মিটার দূরে।',
      'voice_ambulance_on_scene_volunteer':
          'অ্যাম্বুলেন্স ঘটনাস্থলে — ঘটনাস্থল থেকে প্রায় দুইশো মিটারের মধ্যে।',
      'voice_ambulance_returning': 'অ্যাম্বুলেন্স হাসপাতালে ফিরছে।',
      'voice_response_complete_station':
          'প্রতিক্রিয়া সম্পূর্ণ। অ্যাম্বুলেন্স স্টেশনে।',
      'voice_response_complete_cycle':
          'প্রতিক্রিয়া সম্পূর্ণ। অ্যাম্বুলেন্স স্টেশনে। মোট চক্র {minutes} মিনিট {seconds} সেকেন্ড।',
      'voice_volunteers_on_scene_count':
          '{n} জন স্বেচ্ছাসেবক এখন ঘটনাস্থলে।',
      'voice_one_volunteer_on_scene': 'একজন স্বেচ্ছাসেবক ঘটনাস্থলে।',
      'voice_ptt_joined_comms': '{who} ভয়েস যোগাযোগে যোগ দিয়েছেন।',
      'voice_tts_unavailable_banner':
          'ভয়েস নির্দেশনা উপলব্ধ নয় — স্ক্রিনের লেখা পড়ুন।',
      'language_picker_title': 'ভাষা',
      'volunteer_victim_medical_card': 'ভুক্তভোগী মেডিকেল কার্ড',
      'volunteer_dispatch_milestone_title': 'ডিসপ্যাচ আপডেট',
      'volunteer_dispatch_milestone_hospital': 'হাসপাতাল গ্রহণ: {hospital}',
      'volunteer_dispatch_milestone_unit': 'অ্যাম্বুলেন্স ইউনিট: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'অ্যাম্বুলেন্স ক্রু: সমন্বয়…',
      'volunteer_dispatch_milestone_en_route': 'অ্যাম্বুলেন্স পথে',
      'volunteer_triage_qr_report_title': 'QR বা ট্যাপ রিপোর্ট',
      'volunteer_triage_qr_report_subtitle':
          'হ্যান্ডঅফের জন্য কোড স্ক্যান করুন বা ঘটনার রিপোর্ট সেভ করতে ট্যাপ করুন।',
      'volunteer_triage_show_qr': 'QR দেখান',
      'volunteer_triage_tap_report': 'রিপোর্ট',
      'volunteer_triage_qr_title': 'ঘটনা হ্যান্ডঅফ QR',
      'volunteer_triage_qr_body': 'কাঠামোগত ডেটার জন্য স্টাফ বা EMS-এর সাথে শেয়ার করুন।',
      'volunteer_triage_report_saved': 'রিপোর্ট এই ঘটনার অধীনে সংরক্ষিত।',
      'volunteer_triage_report_failed': 'রিপোর্ট সংরক্ষণ ব্যর্থ: ',
      'volunteer_victim_medical_offline_hint': 'SOS প্যাকেট থেকে — অফলাইনে ক্যাশে।',
      'volunteer_victim_consciousness_title': 'সচেতনতা',
      'volunteer_victim_three_questions': 'প্রাথমিক উত্তর',
      'volunteer_major_updates_log': 'শুধু গুরুত্বপূর্ণ আপডেট',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'টিয়ার {tier} এ উন্নীত করছি। হাসপাতাল {hospital} চেষ্টা করছি।',
      'volunteer_dispatch_trying_hospital': 'হাসপাতাল {hospital} চেষ্টা করছি।',
      'volunteer_dispatch_hospital_accepted':
          '{hospital} জরুরি গ্রহণ করেছে। অ্যাম্বুলেন্স সমন্বয় চলছে।',
      'volunteer_dispatch_all_hospitals_notified':
          'সব হাসপাতালকে জানানো হয়েছে। জরুরি সেবায় এসকেলেট করছি।',
      'sos_dispatch_alerting_nearest_trying':
          'আপনার এলাকার নিকটতম হাসপাতালে সতর্ক করছি। {hospital} চেষ্টা করছি।',
      'sos_dispatch_escalating_tier_trying':
          'কোনো সাড়া নেই। টিয়ার {tier} এ উন্নীত করছি। {hospital} চেষ্টা করছি।',
      'sos_dispatch_retry_previous_trying':
          'আগের হাসপাতাল থেকে সাড়া নেই। {hospital} চেষ্টা করছি।',
      'sos_dispatch_all_hospitals_call_112':
          'সব হাসপাতালকে জানানো হয়েছে। জরুরি সেবার জন্য ১১২ কল করুন।',
      'quick_sos_victim_breathing_q': 'ব্যক্তি শ্বাস নিচ্ছে?',
      'quick_sos_label_yes': 'হ্যাঁ',
      'quick_sos_label_no': 'না',
      'quick_sos_label_unsure': 'নিশ্চিত নয়',
      'quick_sos_person': 'ব্যক্তি',
      'quick_sos_people': 'ব্যক্তি',
      'quick_sos_people_three_plus': '৩+',
      'login_tagline': 'প্রাণ বাঁচাই',
      'login_subtitle':
          'জরুরি রিপোর্ট করুন, স্বেচ্ছাসেবকদের সঙ্গে সমন্বয় করুন, গোল্ডেন আওয়ারে প্রাণ বাঁচান।',
      'login_continue_google': 'Google দিয়ে চালিয়ে যান',
      'login_continue_phone': 'ফোন দিয়ে চালিয়ে যান',
      'login_send_code': 'যাচাইকরণ কোড পাঠান',
      'login_verify_login': 'যাচাই করে লগ ইন',
      'login_phone_label': 'ফোন নম্বর',
      'login_phone_hint': '+8801XXXXXXXXX',
      'login_otp_label': 'যাচাইকরণ কোড (OTP)',
      'login_back_options': 'বিকল্পে ফিরুন',
      'login_change_phone': 'ফোন নম্বর পরিবর্তন',
      'login_drill_mode': 'ড্রিল মোড',
      'login_drill_subtitle': 'অনুশীলনের জন্য ট্যাপ — আসল SOS নয়',
      'login_drill_semantics': 'ড্রিল মোড, আসল জরুরি ছাড়া অনুশীলন',
      'login_practise_victim': 'কর্তৃগত হিসেবে অনুশীলন',
      'login_practise_volunteer': 'স্বেচ্ছাসেবক হিসেবে অনুশীলন',
      'login_admin_note':
          'মাস্টার কনসোল: আলাদা অ্যাকাউন্ট নেই — নিচে ট্যাপ করুন। লগ ইন না থাকলে হালকা বেনামি সেশন।',
      'login_ems_dashboard': 'EMS ড্যাশবোর্ড',
      'login_emergency_operator': 'জরুরি সেবা অপারেটর লগ ইন',
      'ai_assist_practice_banner':
          'অনুশীলন Lifeline — আসল ডিসপ্যাচে কিছু যায় না।',
      'ai_assist_rail_semantics': 'Lifeline স্তর {n}: {title}',
      'ai_assist_emergency_toggle_on': 'জরুরি মোড চালু, তাৎক্ষণিক গাইড',
      'ai_assist_emergency_toggle_off': 'জরুরি মোড বন্ধ',
      'dashboard_exit_drill_title': 'ড্রিল মোড থেকে বের হবেন?',
      'dashboard_exit_drill_body':
          'আপনি এই অনুশীলন সেশন থেকে সাইন আউট হয়ে লগইনে ফিরবেন।',
      'dashboard_back_login_tooltip': 'লগইনে ফিরুন',
      'dashboard_exit_drill_confirm': 'প্রস্থান',
      'sos_active_title_big': 'সক্রিয় SOS',
      'sos_active_help_coming': 'সাহায্য আসছে। শান্ত থাকুন।',
      'sos_active_badge_waiting': 'অপেক্ষমাণ',
      'sos_active_badge_en_route_count': '{n} পথে',
      'sos_active_mini_ambulance': 'অ্যাম্বুলেন্স',
      'sos_active_mini_on_scene': 'ঘটনাস্থলে',
      'sos_active_mini_status': 'অবস্থা',
      'sos_active_volunteers_count_short': '{n} স্বেচ্ছাসেবক',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title':
          'সব হাসপাতালকে জানানো হয়েছে',
      'sos_active_all_hospitals_notified_subtitle':
          'সময়মতো কোনো হাসপাতাল গ্রহণ করেনি। ডিসপ্যাচ জরুরি সেবায় এস্কেলেট করছে।',
      'sos_active_position_refresh_note':
          'ব্যাটারি সাশ্রয়ের জন্য SOS চলাকালীন আপনার অবস্থান প্রতি প্রায় ৪৫ সেকেন্ডে রিফ্রেশ হয়। অ্যাপ খোলা রাখুন এবং সম্ভব হলে চার্জে লাগান।',
      'sos_active_mic_active': 'মাইক · সক্রিয়',
      'sos_active_mic_active_detail':
          'লাইভ চ্যানেল আপনার মাইক্রোফোন গ্রহণ করছে।',
      'sos_active_mic_standby': 'মাইক · স্ট্যান্ডবাই',
      'sos_active_mic_standby_detail': 'ভয়েস চ্যানেলের অপেক্ষায়…',
      'sos_active_mic_connecting': 'মাইক · সংযুক্ত হচ্ছে',
      'sos_active_mic_connecting_detail':
          'জরুরি ভয়েস চ্যানেলে যোগ দিচ্ছে…',
      'sos_active_mic_reconnecting': 'মাইক · পুনঃসংযোগ',
      'sos_active_mic_reconnecting_detail':
          'লাইভ অডিও পুনরুদ্ধার করা হচ্ছে…',
      'sos_active_mic_failed': 'মাইক · ব্যাহত',
      'sos_active_mic_failed_detail':
          'ভয়েস চ্যানেল অনুপলব্ধ। উপরের RETRY ব্যবহার করুন।',
      'sos_active_mic_ptt_only': 'মাইক · ঘটনা চ্যানেল',
      'sos_active_mic_ptt_only_detail':
          'অপারেশনস কনসোল Firebase PTT-এর মাধ্যমে ভয়েস রুট করেছে। সাড়া দেওয়ার জন্য ব্রডকাস্ট চেপে ধরুন।',
      'sos_active_mic_interrupted': 'মাইক · বিঘ্নিত',
      'sos_active_mic_interrupted_detail':
          'অ্যাপ অডিও প্রসেস করার সময় সংক্ষিপ্ত বিরতি।',
      'sos_active_consciousness_note':
          'চেতনা পরীক্ষায় হ্যাঁ বা না দিয়ে উত্তর দিন; অন্যান্য প্রম্পট স্ক্রিন বিকল্প ব্যবহার করে।',
      'sos_active_live_updates_header': 'লাইভ আপডেট',
      'sos_active_live_updates_subtitle':
          'ডিসপ্যাচ, স্বেচ্ছাসেবক ও ডিভাইস',
      'sos_active_live_tag': 'লাইভ',
      'sos_active_activity_log': 'কার্যকলাপ লগ',
      'sos_active_header_stat_coordinating_crew': 'দল সমন্বয়',
      'sos_active_header_stat_coordinating': 'সমন্বয়',
      'sos_active_header_stat_en_route': 'পথে',
      'sos_active_header_stat_route_min': '~{n} মিনিট',
      'sos_active_live_sos_is_live_title': 'SOS লাইভ',
      'sos_active_live_sos_is_live_detail':
          'আপনার অবস্থান ও মেডিকেল ফ্ল্যাগ জরুরি নেটওয়ার্কে রয়েছে।',
      'sos_active_live_volunteers_notified_title':
          'স্বেচ্ছাসেবকদের অবহিত',
      'sos_active_live_volunteers_notified_detail':
          'কাছের স্বেচ্ছাসেবকরা এই ঘটনা রিয়েল টাইমে পাচ্ছেন।',
      'sos_active_live_bridge_connected_title':
          'জরুরি ভয়েস ব্রিজ সংযুক্ত',
      'sos_active_live_bridge_connected_detail':
          'ডিসপ্যাচ ডেস্ক ও সাড়াদানকারীরা এই চ্যানেল শুনতে পান।',
      'sos_active_live_ptt_title': 'Firebase PTT-এর মাধ্যমে ভয়েস',
      'sos_active_live_ptt_detail':
          'এই ফ্লিটের জন্য লাইভ WebRTC ব্রিজ বন্ধ। ভয়েস ও টেক্সট আপডেটের জন্য ব্রডকাস্ট ব্যবহার করুন।',
      'sos_active_live_contacts_notified_title':
          'জরুরি যোগাযোগদের অবহিত',
      'sos_active_live_hospital_accepted_title': 'হাসপাতাল গ্রহণ করেছে',
      'sos_active_live_ambulance_unit_assigned_title':
          'অ্যাম্বুলেন্স ইউনিট নিযুক্ত',
      'sos_active_live_ambulance_unit_assigned_subtitle': 'ইউনিট {unit}',
      'sos_active_live_ambulance_en_route_title': 'অ্যাম্বুলেন্স পথে',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'পথে',
      'sos_active_live_ambulance_en_route_route_eta': '~{n} মিনিট (রুট)',
      'sos_active_live_ambulance_coordination_title': 'অ্যাম্বুলেন্স সমন্বয়',
      'sos_active_live_ambulance_coordination_pending':
          'হাসপাতাল গ্রহণ করেছে — অ্যাম্বুলেন্স অপারেটরদের জানানো হচ্ছে।',
      'sos_active_live_ambulance_coordination_arranging':
          'অ্যাম্বুলেন্স ক্রু ব্যবস্থা — ইউনিট পথে থাকলে মিনিট ETA।',
      'sos_active_live_responder_status_title': 'সাড়াদানকারীর অবস্থা',
      'sos_active_live_volunteer_accepted_single_title':
          'স্বেচ্ছাসেবক গ্রহণ করেছে',
      'sos_active_live_volunteer_accepted_many_title':
          'স্বেচ্ছাসেবকরা গ্রহণ করেছে',
      'sos_active_live_volunteer_accepted_single_detail':
          'একজন সাড়াদানকারী নিযুক্ত এবং আপনার দিকে আসছে।',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} জন সাড়াদানকারী এই SOS-এ নিযুক্ত।',
      'sos_active_live_volunteer_on_scene_single_title':
          'স্বেচ্ছাসেবক ঘটনাস্থলে পৌঁছেছে',
      'sos_active_live_volunteer_on_scene_many_title':
          'স্বেচ্ছাসেবকরা ঘটনাস্থলে',
      'sos_active_live_volunteer_on_scene_single_detail':
          'কেউ আপনার সাথে বা আপনার পিনে আছে।',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} জন সাড়াদানকারী ঘটনাস্থলে চিহ্নিত।',
      'sos_active_live_responder_location_title':
          'লাইভ সাড়াদানকারীর অবস্থান',
      'sos_active_live_responder_location_detail':
          'নিযুক্ত স্বেচ্ছাসেবকের GPS মানচিত্রে আপডেট হচ্ছে।',
      'sos_active_live_professional_dispatch_title':
          'পেশাদার ডিসপ্যাচ সক্রিয়',
      'sos_active_live_professional_dispatch_detail':
          'সমন্বিত পরিষেবা এই ঘটনায় কাজ করছে।',
      'sos_active_ambulance_200m_detail':
          'অ্যাম্বুলেন্স ঘটনাস্থলে — প্রায় ২০০ মিটারের মধ্যে।',
      'sos_active_ambulance_200m_semantic_label':
          'অ্যাম্বুলেন্স প্রায় দুশো মিটারের মধ্যে ঘটনাস্থলে',
      'sos_active_bridge_channel_on_suffix': ' · {n} চ্যানেলে',
      'sos_active_bridge_channel_voice': 'জরুরি ভয়েস চ্যানেল',
      'sos_active_bridge_channel_ptt': 'জরুরি চ্যানেল · Firebase PTT',
      'sos_active_bridge_channel_failed':
          'জরুরি চ্যানেল · পুনরায় চেষ্টা করুন',
      'sos_active_bridge_channel_connecting':
          'জরুরি চ্যানেল · সংযুক্ত হচ্ছে',
      'sos_active_dispatch_contact_hospitals_default':
          'আপনার অবস্থান ও জরুরি প্রকারের উপর ভিত্তি করে কাছের হাসপাতালগুলির সাথে যোগাযোগ করা হচ্ছে।',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'অ্যাম্বুলেন্স ক্রুকে জানানো হয়েছে',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'পার্টনার হাসপাতাল আপনার কেস গ্রহণ করেছে। অ্যাম্বুলেন্স অপারেটরদের জানানো হচ্ছে।',
      'sos_active_dispatch_ambulance_confirmed_title':
          'অ্যাম্বুলেন্স নিশ্চিত',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'ইউনিট {unit} আপনার দিকে আসছে। সাড়াদানকারীরা পৌঁছাতে পারে এমন জায়গায় থাকুন।',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'একটি অ্যাম্বুলেন্স আপনার দিকে আসছে। সাড়াদানকারীরা পৌঁছাতে পারে এমন জায়গায় থাকুন।',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'অ্যাম্বুলেন্স হস্তান্তরে বিলম্ব',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'হাসপাতাল গ্রহণ করেছে, কিন্তু সময়ে কোনো অ্যাম্বুলেন্স ক্রু নিশ্চিত হয়নি। ডিসপ্যাচ এস্কেলেট করছে — প্রয়োজনে ১১২-এ কল করুন।',
      'sos_active_dispatch_pending_title_trying': 'চেষ্টা: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · হাসপাতালের প্রতিক্রিয়ার অপেক্ষা।',
      'sos_active_dispatch_accepted_title': '{hospital} গ্রহণ করেছে',
      'sos_active_dispatch_accepted_subtitle':
          'অ্যাম্বুলেন্স ডিসপ্যাচ সমন্বয় করা হচ্ছে।',
      'sos_active_dispatch_exhausted_title':
          'সব হাসপাতালকে জানানো হয়েছে',
      'sos_active_dispatch_exhausted_subtitle':
          'সময়মতো কোনো হাসপাতাল গ্রহণ করেনি। ডিসপ্যাচ জরুরি সেবায় এস্কেলেট করছে।',
      'sos_active_dispatch_generic_title': 'হাসপাতাল ডিসপ্যাচ',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'জরুরি ভয়েস চ্যানেল',
      'volunteer_bridge_join_hint_incident':
          'যোগ দিতে এই ঘটনাটি ব্যবহৃত হয়: আপনার নম্বর মিললে জরুরি যোগাযোগ; নইলে গৃহীত স্বেচ্ছাসেবক।',
      'volunteer_bridge_join_hint_elite':
          'আপনি গৃহীত সাড়াদানকারী হলে যোগদান আপনার এলিট স্বেচ্ছাসেবক অ্যাক্সেস ব্যবহার করে; নইলে নম্বর মিললে যোগাযোগ।',
      'volunteer_bridge_join_hint_desk':
          'আপনার প্রোফাইলের জরুরি সেবা ডেস্ক হিসেবে আপনি ডিসপ্যাচ হিসেবে যোগ দেন।',
      'volunteer_bridge_join_voice_btn': 'ভয়েসে যোগ দিন',
      'volunteer_bridge_connecting_btn': 'সংযুক্ত হচ্ছে…',
      'volunteer_bridge_incident_id_hint': 'ঘটনা ID',
      'volunteer_consignment_live_location_hint':
          'আপনি কনসাইনমেন্টে থাকাকালীন, মানচিত্র ও ETA সঠিক রাখতে আপনার লাইভ অবস্থান এই ঘটনার সাথে শেয়ার করা হয়।',
      'volunteer_consignment_low_power_label': 'লো পাওয়ার',
      'volunteer_consignment_normal_gps_label': 'সাধারণ GPS',
      'bridge_card_incident_id_missing': 'ঘটনা ID অনুপস্থিত।',
      'bridge_card_ptt_only_snackbar':
          'অপারেশন কনসোল ভিকটিমের ভয়েস Firebase PTT এর মাধ্যমে পাঠিয়েছে। WebRTC ব্রিজে যোগদান নিষ্ক্রিয়।',
      'bridge_card_ptt_only_banner':
          'কনসোল Firebase PTT এর মাধ্যমে ভয়েস পাঠিয়েছে — এই ফ্লিটের জন্য LiveKit ব্রিজে যোগদান নিষ্ক্রিয়।',
      'bridge_card_connected_snackbar': 'ভয়েস চ্যানেলে সংযুক্ত হয়েছেন।',
      'bridge_card_could_not_join': 'যোগদান করা যায়নি: {err}',
      'bridge_card_voice_channel_title': 'ভয়েস চ্যানেল',
      'bridge_card_calm_disclaimer':
          'শান্ত থাকুন এবং পরিষ্কারভাবে কথা বলুন। স্থিতিশীল স্বর ভিকটিম এবং অন্যান্য সহায়তাকারীদের সাহায্য করে। চিৎকার বা তাড়াহুড়া করে কথা বলবেন না।',
      'bridge_card_cancel': 'বাতিল',
      'bridge_card_join_voice': 'ভয়েসে যোগ দিন',
      'bridge_card_voice_connected': 'ভয়েস সংযুক্ত',
      'bridge_card_in_channel': 'চ্যানেলে {n} জন',
      'bridge_card_transmitting': 'প্রেরণ করা হচ্ছে…',
      'bridge_card_hold_to_talk': 'কথা বলতে ধরে রাখুন',
      'bridge_card_disconnect': 'সংযোগ বিচ্ছিন্ন',
      'vol_ems_banner_en_route': 'অ্যাম্বুলেন্স ঘটনাস্থলের দিকে যাচ্ছে',
      'vol_ems_banner_on_scene': 'অ্যাম্বুলেন্স স্থানে (~200 মি)',
      'vol_ems_banner_returning': 'অ্যাম্বুলেন্স হাসপাতালে ফিরছে',
      'vol_ems_banner_complete': 'প্রতিক্রিয়া সম্পূর্ণ · অ্যাম্বুলেন্স স্টেশনে',
      'vol_ems_banner_complete_with_cycle':
          'প্রতিক্রিয়া সম্পূর্ণ · অ্যাম্বুলেন্স স্টেশনে · মোট চক্র {m}মি {s}সে',
      'vol_tooltip_lifeline_first_aid':
          'লাইফলাইন — প্রাথমিক চিকিৎসা গাইড (প্রতিক্রিয়ায় থাকে)',
      'vol_tooltip_exit_mission': 'মিশন প্রস্থান',
      'vol_low_power_tracking_hint':
          'লো-পাওয়ার ট্র্যাকিং: আমরা আপনার অবস্থান কম বার, বড় নড়াচড়ার পরেই সিঙ্ক করি। ডিসপ্যাচ এখনও আপনার শেষ পয়েন্ট দেখতে পায়।',
      'vol_marker_you': 'আপনি',
      'vol_marker_active_unit': 'সক্রিয় ইউনিট',
      'vol_marker_practice_incident': 'অনুশীলন ঘটনা',
      'vol_marker_accident_scene': 'দুর্ঘটনাস্থল',
      'vol_marker_training_pin': 'প্রশিক্ষণ পিন — সত্যিকারের SOS নয়',
      'vol_marker_high_severity': 'GITM কলেজ - উচ্চ গুরুতরতা',
      'vol_marker_accepted_hospital': 'গৃহীত: {hospital}',
      'vol_marker_trying_hospital': 'চেষ্টা: {hospital}',
      'vol_marker_ambulance_on_scene': 'অ্যাম্বুলেন্স স্থানে!',
      'vol_marker_ambulance_en_route': 'অ্যাম্বুলেন্স পথে',
      'vol_badge_at_scene_pin': 'স্থান পিনে',
      'vol_badge_in_5km_zone': '5 কিমি অঞ্চলে',
      'vol_badge_en_route': 'পথে',
    },

    // ── Marathi (मराठी) ────────────────────────────────────────────────────
    'mr': {
      'app_name': 'EmergencyOS',
      'profile_title': 'प्रोफाइल आणि वैद्यकीय ओळख',
      'language': 'भाषा',
      'save_medical_profile': 'वैद्यकीय प्रोफाइल जतन करा',
      'critical_medical_info': 'महत्त्वाची वैद्यकीय माहिती',
      'emergency_contacts': 'आपत्कालीन संपर्क',
      'golden_hour_details': 'गोल्डन अवर तपशील',
      'sos_lock': 'SOS लॉक',
      'top_life_savers': 'शीर्ष जीवनरक्षक',
      'lives_saved': 'वाचवलेले जीव',
      'active_alerts': 'सक्रिय सूचना',
      'rank': 'रँक',
      'on_duty': 'ड्युटीवर',
      'standby': 'स्टँडबाय',
      'sos': 'SOS',
      'call_now': 'आत्ता कॉल करा',
      'quick_guide': 'जलद मार्गदर्शक',
      'detailed_instructions': 'तपशीलवार सूचना',
      'red_flags': 'धोक्याचे संकेत',
      'cautions': 'सावधगिरी',
      'voice_walkthrough': 'व्हॉइस मार्गदर्शन',
      'playing': 'प्ले होत आहे...',
      'swipe_next_guide': 'पुढील मार्गदर्शकासाठी स्वाइप करा',
      'watch_video_guide': 'संपूर्ण व्हिडिओ मार्गदर्शक पहा',
      'emergency_grid_scan': 'आपत्कालीन ग्रिड स्कॅन',
      'area_telemetry': 'क्षेत्र टेलिमेट्री आणि जोखीम निर्देशांक',
      'report_hazard': 'धोका नोंदवा',
      'todays_duty': 'आजची ड्युटी',
      'blood_type': 'रक्तगट',
      'allergies': 'ॲलर्जी',
      'medical_conditions': 'वैद्यकीय स्थिती',
      'contact_name': 'प्राथमिक संपर्क नाव',
      'contact_phone': 'प्राथमिक संपर्क फोन',
      'relationship': 'नाते',
      'medications': 'सध्याची औषधे',
      'organ_donor': 'अवयवदान स्थिती',
      'good_morning': 'सुप्रभात,',
      'good_afternoon': 'शुभ दुपार,',
      'good_evening': 'शुभ संध्याकाळ,',
      'hospitals': 'रुग्णालये',
      'visual_walkthrough': 'दृश्य मार्गदर्शन',
      'lifeline': 'लाइफलाइन',
      'nav_home': 'होम',
      'nav_map': 'नकाशा',
      'nav_grid': 'ग्रिड',
      'nav_profile': 'प्रोफाइल',
      'map_caching_offline_pct': 'ऑफलाइनसाठी क्षेत्र कॅश होत आहे — {pct}%',
      'map_drill_practice_banner':
          'सराव ग्रिड: पल्सिंग पिन = डेमो सक्रिय सतर्कता. थरांसाठी नकाशा फिल्टर — खरे डेटा नाही.',
      'map_recenter_tooltip': 'पुन्हा केंद्रित करा',
      'map_legend_hospital': 'रुग्णालय',
      'map_legend_live_sos_history': 'लाइव्ह SOS / इतिहास',
      'map_legend_past_this_hex': 'मागील (हा हेक्स)',
      'map_legend_in_area': 'क्षेत्रात {n}',
      'map_legend_in_cell': 'सेलमध्ये {n}',
      'map_legend_volunteers_on_duty': 'ड्युटीवर स्वयंसेवक',
      'map_legend_volunteers_in_grid': 'ग्रिडमध्ये {n}',
      'map_legend_responder_scene': 'प्रतिसाद देणारा → दृश्य',
      'map_responder_routes_one': '{n} मार्ग',
      'map_responder_routes_many': '{n} मार्ग',
      'map_filters_title': 'नकाशा फिल्टर',
      'step_prefix': 'पायरी',
      'highlights_steps': 'एक एक करून पायऱ्या दाखवतो',
      'offline_mode': 'ऑफलाइन — नेटवर्क डिस्कनेक्ट',
      'volunteer': 'स्वयंसेवक',
      'unranked': 'रँक नाही',
      'live': 'लाइव्ह',
      'you': 'तुम्ही',
      'saved': 'वाचवले',
      'xp_responses': 'XP · {0} प्रतिसाद',
      'duty_monitoring': 'तुम्ही ड्युटीवर असताना SOS पॉप-अप चालू आहेत.',
      'turn_on_duty_msg': 'SOS पॉप-अप मिळवण्यासाठी ड्युटी चालू करा.',
      'on_duty_snack': 'ड्युटीवर — तुमच्या परिसरातील घटनांचे निरीक्षण...',
      'off_duty_snack': 'स्टँडबाय — ड्युटी सत्र नोंदवले.',
      'leaderboard_offline': 'लीडरबोर्ड ऑफलाइन',
      'leaderboard_offline_sub': 'सिंकिंग थांबले. कॅश्ड स्कोर.',
      'set_sos_pin_first': 'प्रथम SOS पिन सेट करा',
      'set_pin_safety_msg': 'सुरक्षिततेसाठी, SOS तयार करण्यापूर्वी पिन सेट करणे आवश्यक आहे.',
      'set_pin_now': 'आत्ता पिन सेट करा',
      'later': 'नंतर',
      'sos_are_you_conscious':
          'तुम्ही होशीत आहात? कृपया होय किंवा नाही उत्तर द्या.',
      'sos_tts_opening_guidance':
          'तुमचे SOS सक्रिय आहे. मदत येत आहे. बोललेले सूचना पाळा आणि उत्तर देण्यास टॅप करा.',
      'sos_interview_q1_prompt': 'काय घडत आहे? (आपत्कालीन प्रकार)',
      'sos_interview_q2_prompt': 'तुम्ही सुरक्षित आहात? किती गंभीर?',
      'sos_interview_q3_prompt': 'किती लोक सामील आहेत?',
      'sos_chip_cat_accident': 'अपघात',
      'sos_chip_cat_medical': 'वैद्यकीय',
      'sos_chip_cat_hazard': 'धोका (आग, बुडणे इ.)',
      'sos_chip_cat_assault': 'हल्ला',
      'sos_chip_cat_other': 'इतर',
      'sos_chip_safe_critical': 'गंभीर (जीवाला धोका)',
      'sos_chip_safe_injured': 'जखमी पण स्थिर',
      'sos_chip_safe_danger': 'जखमी नाही पण धोक्यात',
      'sos_chip_safe_safe_now': 'आता सुरक्षित',
      'sos_chip_people_me': 'फक्त मी',
      'sos_chip_people_two': 'दोघे',
      'sos_chip_people_many': 'दोघांपेक्षा जास्त',
      'sos_tts_interview_saved':
          'सर्व मुलाखत डेटा जतन केला. प्रतिसादकर्त्यांना तपशील आहेत.',
      'sos_tts_map_routes':
          'नकाशा टॅब उघडा: ठोस लाल नियुक्त रुग्णालयाचा रस्ता किंवा जवळचा मार्ग; हिरवा स्वयंसेवक मार्ग. आपत्कालीन आवाज चॅनेलवर रहा.',
      'sos_tts_emergency_contacts_on_file':
          'Your emergency contact from your profile is attached to this SOS. SMS updates may be sent when that option is enabled.',
      'sos_tts_conscious_no_answer_attempt':
          'उत्तर नाही. होश तपासणी {max} पैकी {n}. एका मिनिटात पुन्हा विचारू.',
      'voice_volunteer_accepted':
          'स्वयंसेवकाने स्वीकारले. मदत येत आहे.',
      'voice_ambulance_dispatched_eta':
          'रुग्णवाहिका पाठवली. अंदाजे आगमन: {eta}.',
      'voice_police_dispatched_eta':
          'पोलीस पाठवले. अंदाजे आगमन: {eta}.',
      'voice_ambulance_on_scene_victim':
          'रुग्णवाहिका जागेवर आहे — तुमच्यापासून अंदाजे दोनशे मीटर अंतरावर.',
      'voice_ambulance_on_scene_volunteer':
          'रुग्णवाहिका जागेवर आहे — घटनास्थळापासून अंदाजे दोनशे मीटर आत.',
      'voice_ambulance_returning': 'रुग्णवाहिका रुग्णालयाकडे परत येत आहे.',
      'voice_response_complete_station':
          'प्रतिसाद पूर्ण. रुग्णवाहिका स्टेशनवर.',
      'voice_response_complete_cycle':
          'प्रतिसाद पूर्ण. रुग्णवाहिका स्टेशनवर. एकूण चक्र {minutes} मिनिटे {seconds} सेकंद.',
      'voice_volunteers_on_scene_count':
          '{n} स्वयंसेवक आता जागेवर आहेत.',
      'voice_one_volunteer_on_scene': 'एक स्वयंसेवक जागेवर आहे.',
      'voice_ptt_joined_comms': '{who} आवाज संवादात सामील झाले.',
      'voice_tts_unavailable_banner':
          'आवाज मार्गदर्शन उपलब्ध नाही — स्क्रीनवरील मजकूर वाचा.',
      'language_picker_title': 'भाषा',
      'volunteer_victim_medical_card': 'बाधित वैद्यकीय कार्ड',
      'volunteer_dispatch_milestone_title': 'डिस्पॅच अपडेट',
      'volunteer_dispatch_milestone_hospital': 'रुग्णालय स्वीकारले: {hospital}',
      'volunteer_dispatch_milestone_unit': 'रुग्णवाहिका युनिट: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'रुग्णवाहिका क्रू: समन्वय…',
      'volunteer_dispatch_milestone_en_route': 'रुग्णवाहिका मार्गावर',
      'volunteer_triage_qr_report_title': 'QR किंवा टॅप अहवाल',
      'volunteer_triage_qr_report_subtitle':
          'हँडऑफसाठी कोड स्कॅन करा किंवा घटनेचा अहवाल जतन करण्यासाठी टॅप करा.',
      'volunteer_triage_show_qr': 'QR दाखवा',
      'volunteer_triage_tap_report': 'अहवाल',
      'volunteer_triage_qr_title': 'घटना हँडऑफ QR',
      'volunteer_triage_qr_body': 'संरचित डेटासाठी कर्मचारी किंवा EMS सोबत शेअर करा.',
      'volunteer_triage_report_saved': 'अहवाल या घटनेखाली जतन केला.',
      'volunteer_triage_report_failed': 'अहवाल जतन करता आला नाही: ',
      'volunteer_victim_medical_offline_hint': 'SOS पॅकेटमधून — ऑफलाइन कॅशमधून.',
      'volunteer_victim_consciousness_title': 'होश',
      'volunteer_victim_three_questions': 'सुरुवातीची उत्तरे',
      'volunteer_major_updates_log': 'फक्त मुख्य अपडेट',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'टियर {tier} पर्यंत वाढवत आहोत. रुग्णालय {hospital} प्रयत्न करत आहोत.',
      'volunteer_dispatch_trying_hospital': 'रुग्णालय {hospital} प्रयत्न करत आहोत.',
      'volunteer_dispatch_hospital_accepted':
          '{hospital} ने आपत्काल स्वीकारला. रुग्णवाहिका समन्वय सुरू आहे.',
      'volunteer_dispatch_all_hospitals_notified':
          'सर्व रुग्णालयांना कळवले. आपत्कालीन सेवांकडे पाठवत आहोत.',
      'sos_dispatch_alerting_nearest_trying':
          'तुमच्या क्षेत्रातील जवळच्या रुग्णालयाला सूचित करत आहोत. {hospital} प्रयत्न करत आहोत.',
      'sos_dispatch_escalating_tier_trying':
          'प्रतिसाद नाही. टियर {tier} पर्यंत वाढवत आहोत. {hospital} प्रयत्न करत आहोत.',
      'sos_dispatch_retry_previous_trying':
          'मागील रुग्णालयाकडून प्रतिसाद नाही. {hospital} प्रयत्न करत आहोत.',
      'sos_dispatch_all_hospitals_call_112':
          'सर्व रुग्णालयांना कळवले. आपत्कालीन सेवांसाठी कृपया 112 वर कॉल करा.',
      'sos_active_title_big': 'सक्रिय SOS',
      'sos_active_help_coming': 'मदत येत आहे. शांत रहा.',
      'sos_active_badge_waiting': 'प्रतीक्षेत',
      'sos_active_badge_en_route_count': '{n} वाटेवर',
      'sos_active_mini_ambulance': 'रुग्णवाहिका',
      'sos_active_mini_on_scene': 'घटनास्थळी',
      'sos_active_mini_status': 'स्थिती',
      'sos_active_volunteers_count_short': '{n} स्वयंसेवक',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title':
          'सर्व रुग्णालयांना कळवले',
      'sos_active_all_hospitals_notified_subtitle':
          'वेळेत कोणतेही रुग्णालय स्वीकारले नाही. डिस्पॅच आपत्कालीन सेवांकडे एस्कलेट करत आहे.',
      'sos_active_position_refresh_note':
          'बॅटरी वाचवण्यासाठी SOS दरम्यान तुमचे स्थान सुमारे दर 45 सेकंदांनी रिफ्रेश होते. ॲप उघडे ठेवा आणि शक्य असल्यास चार्जिंगला लावा.',
      'sos_active_mic_active': 'माइक · सक्रिय',
      'sos_active_mic_active_detail':
          'लाइव्ह चॅनेल तुमचा मायक्रोफोन ऐकत आहे.',
      'sos_active_mic_standby': 'माइक · स्टँडबाय',
      'sos_active_mic_standby_detail': 'व्हॉइस चॅनेलची प्रतीक्षा…',
      'sos_active_mic_connecting': 'माइक · कनेक्ट होत आहे',
      'sos_active_mic_connecting_detail':
          'आपत्कालीन व्हॉइस चॅनेलमध्ये सामील होत आहे…',
      'sos_active_mic_reconnecting': 'माइक · पुन्हा कनेक्ट',
      'sos_active_mic_reconnecting_detail':
          'लाइव्ह ऑडिओ पुनर्संचयित होत आहे…',
      'sos_active_mic_failed': 'माइक · व्यत्यय',
      'sos_active_mic_failed_detail':
          'व्हॉइस चॅनेल उपलब्ध नाही. वरील RETRY वापरा.',
      'sos_active_mic_ptt_only': 'माइक · घटना चॅनेल',
      'sos_active_mic_ptt_only_detail':
          'ऑपरेशन्स कन्सोलने Firebase PTT द्वारे आवाज राउट केला. प्रतिसादकर्त्यांपर्यंत पोहचण्यासाठी ब्रॉडकास्ट दाबून ठेवा.',
      'sos_active_mic_interrupted': 'माइक · व्यत्यय',
      'sos_active_mic_interrupted_detail':
          'ॲप ऑडिओ प्रक्रिया करत असताना थोडा विराम.',
      'sos_active_consciousness_note':
          'शुद्धी तपासणीला होय किंवा नाही ने उत्तर द्या; इतर प्रॉम्प्ट स्क्रीन पर्याय वापरतात.',
      'sos_active_live_updates_header': 'लाइव्ह अद्यतने',
      'sos_active_live_updates_subtitle':
          'डिस्पॅच, स्वयंसेवक आणि डिव्हाइस',
      'sos_active_live_tag': 'लाइव्ह',
      'sos_active_activity_log': 'क्रियाकलाप लॉग',
      'sos_active_header_stat_coordinating_crew': 'टीम समन्वय',
      'sos_active_header_stat_coordinating': 'समन्वय',
      'sos_active_header_stat_en_route': 'वाटेवर',
      'sos_active_header_stat_route_min': '~{n} मिनिटे',
      'sos_active_live_sos_is_live_title': 'SOS लाइव्ह आहे',
      'sos_active_live_sos_is_live_detail':
          'तुमचे स्थान आणि वैद्यकीय ध्वज आपत्कालीन नेटवर्कवर आहेत.',
      'sos_active_live_volunteers_notified_title':
          'स्वयंसेवकांना कळवले',
      'sos_active_live_volunteers_notified_detail':
          'जवळचे स्वयंसेवक ही घटना रिअल टाइममध्ये प्राप्त करतात.',
      'sos_active_live_bridge_connected_title':
          'आपत्कालीन व्हॉइस ब्रिज कनेक्ट',
      'sos_active_live_bridge_connected_detail':
          'डिस्पॅच डेस्क आणि प्रतिसादकर्ते हा चॅनेल ऐकू शकतात.',
      'sos_active_live_ptt_title': 'Firebase PTT द्वारे आवाज',
      'sos_active_live_ptt_detail':
          'या फ्लीटसाठी लाइव्ह WebRTC ब्रिज बंद आहे. आवाज आणि मजकूर अद्यतनांसाठी ब्रॉडकास्ट वापरा.',
      'sos_active_live_contacts_notified_title':
          'आपत्कालीन संपर्कांना कळवले',
      'sos_active_live_hospital_accepted_title': 'रुग्णालयाने स्वीकारले',
      'sos_active_live_ambulance_unit_assigned_title':
          'रुग्णवाहिका युनिट नियुक्त',
      'sos_active_live_ambulance_unit_assigned_subtitle': 'युनिट {unit}',
      'sos_active_live_ambulance_en_route_title': 'रुग्णवाहिका वाटेवर',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'वाटेवर',
      'sos_active_live_ambulance_en_route_route_eta': '~{n} मिनिटे (मार्ग)',
      'sos_active_live_ambulance_coordination_title': 'रुग्णवाहिका समन्वय',
      'sos_active_live_ambulance_coordination_pending':
          'रुग्णालयाने स्वीकारले — रुग्णवाहिका ऑपरेटरांना कळवत आहे.',
      'sos_active_live_ambulance_coordination_arranging':
          'रुग्णवाहिका कर्मचारी व्यवस्था — युनिट वाटेवर असल्यावर मिनिट ETA.',
      'sos_active_live_responder_status_title': 'प्रतिसादकर्त्याची स्थिती',
      'sos_active_live_volunteer_accepted_single_title':
          'स्वयंसेवक स्वीकारले',
      'sos_active_live_volunteer_accepted_many_title':
          'स्वयंसेवकांनी स्वीकारले',
      'sos_active_live_volunteer_accepted_single_detail':
          'एक प्रतिसादकर्ता नियुक्त आहे आणि तुमच्याकडे येत आहे.',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} प्रतिसादकर्ते या SOS साठी नियुक्त आहेत.',
      'sos_active_live_volunteer_on_scene_single_title':
          'स्वयंसेवक घटनास्थळी पोहोचला',
      'sos_active_live_volunteer_on_scene_many_title':
          'स्वयंसेवक घटनास्थळी',
      'sos_active_live_volunteer_on_scene_single_detail':
          'कोणीतरी तुमच्यासोबत किंवा तुमच्या पिनवर आहे.',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} प्रतिसादकर्ते घटनास्थळी चिन्हांकित.',
      'sos_active_live_responder_location_title':
          'लाइव्ह प्रतिसादकर्त्याचे स्थान',
      'sos_active_live_responder_location_detail':
          'नियुक्त स्वयंसेवकाचा GPS नकाशावर अद्यतनित होत आहे.',
      'sos_active_live_professional_dispatch_title':
          'व्यावसायिक डिस्पॅच सक्रिय',
      'sos_active_live_professional_dispatch_detail':
          'समन्वित सेवा या घटनेवर कार्य करत आहेत.',
      'sos_active_ambulance_200m_detail':
          'रुग्णवाहिका घटनास्थळी — सुमारे 200 मीटरच्या आत.',
      'sos_active_ambulance_200m_semantic_label':
          'रुग्णवाहिका सुमारे दोनशे मीटरच्या आत घटनास्थळी',
      'sos_active_bridge_channel_on_suffix': ' · {n} चॅनेलवर',
      'sos_active_bridge_channel_voice': 'आपत्कालीन व्हॉइस चॅनेल',
      'sos_active_bridge_channel_ptt': 'आपत्कालीन चॅनेल · Firebase PTT',
      'sos_active_bridge_channel_failed':
          'आपत्कालीन चॅनेल · पुन्हा प्रयत्न करा',
      'sos_active_bridge_channel_connecting':
          'आपत्कालीन चॅनेल · कनेक्ट होत आहे',
      'sos_active_dispatch_contact_hospitals_default':
          'तुमचे स्थान आणि आपत्कालीन प्रकारावर आधारित आम्ही जवळच्या रुग्णालयांशी संपर्क करत आहोत.',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'रुग्णवाहिका कर्मचाऱ्यांना कळवले',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'भागीदार रुग्णालयाने तुमची केस स्वीकारली. रुग्णवाहिका ऑपरेटरांना कळवत आहोत.',
      'sos_active_dispatch_ambulance_confirmed_title':
          'रुग्णवाहिका पुष्टी',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'युनिट {unit} तुमच्याकडे येत आहे. प्रतिसादकर्ते पोहोचू शकतील अशा ठिकाणी रहा.',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'एक रुग्णवाहिका तुमच्याकडे येत आहे. प्रतिसादकर्ते पोहोचू शकतील अशा ठिकाणी रहा.',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'रुग्णवाहिका हस्तांतरण विलंब',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'रुग्णालयाने स्वीकारले, पण वेळेत कोणते रुग्णवाहिका कर्मचारी पुष्टी केले नाहीत. डिस्पॅच एस्कलेट करत आहे — गरज असल्यास 112 वर कॉल करा.',
      'sos_active_dispatch_pending_title_trying': 'प्रयत्न: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · रुग्णालयाच्या प्रतिसादाची प्रतीक्षा.',
      'sos_active_dispatch_accepted_title': '{hospital} ने स्वीकारले',
      'sos_active_dispatch_accepted_subtitle':
          'रुग्णवाहिका डिस्पॅचचे समन्वय होत आहे.',
      'sos_active_dispatch_exhausted_title':
          'सर्व रुग्णालयांना कळवले',
      'sos_active_dispatch_exhausted_subtitle':
          'वेळेत कोणतेही रुग्णालय स्वीकारले नाही. डिस्पॅच आपत्कालीन सेवांकडे एस्कलेट करत आहे.',
      'sos_active_dispatch_generic_title': 'रुग्णालय डिस्पॅच',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'आपत्कालीन व्हॉइस चॅनेल',
      'volunteer_bridge_join_hint_incident':
          'सामील होण्यासाठी ही घटना वापरली जाते: तुमचा नंबर जुळल्यास आपत्कालीन संपर्क; अन्यथा स्वीकृत स्वयंसेवक.',
      'volunteer_bridge_join_hint_elite':
          'तुम्ही स्वीकृत प्रतिसादकर्ते असताना सामील होणे तुमच्या एलीट प्रवेशाचा वापर करते; अन्यथा नंबर जुळल्यास संपर्क.',
      'volunteer_bridge_join_hint_desk':
          'तुम्ही तुमच्या प्रोफाइलवरील आपत्कालीन सेवा डेस्क म्हणून डिस्पॅच म्हणून सामील होता.',
      'volunteer_bridge_join_voice_btn': 'व्हॉइसमध्ये सामील व्हा',
      'volunteer_bridge_connecting_btn': 'कनेक्ट होत आहे…',
      'volunteer_bridge_incident_id_hint': 'घटना ID',
      'volunteer_consignment_live_location_hint':
          'तुम्ही कन्साइनमेंटवर असताना, नकाशा आणि ETA अचूक ठेवण्यासाठी तुमचे लाइव्ह स्थान या घटनेसह शेअर केले जाते.',
      'volunteer_consignment_low_power_label': 'लो पॉवर',
      'volunteer_consignment_normal_gps_label': 'सामान्य GPS',
      'bridge_card_incident_id_missing': 'घटना ID गहाळ आहे.',
      'bridge_card_ptt_only_snackbar':
          'ऑपरेशन्स कन्सोलने बळीचा आवाज Firebase PTT द्वारे पाठवला. WebRTC पूल जॉइन निष्क्रिय.',
      'bridge_card_ptt_only_banner':
          'कन्सोलने Firebase PTT द्वारे आवाज पाठवला — या फ्लीटसाठी LiveKit पूल जॉइन निष्क्रिय.',
      'bridge_card_connected_snackbar': 'व्हॉइस चॅनेलशी कनेक्ट झाले.',
      'bridge_card_could_not_join': 'जॉइन होता आले नाही: {err}',
      'bridge_card_voice_channel_title': 'व्हॉइस चॅनेल',
      'bridge_card_calm_disclaimer':
          'शांत राहा आणि स्पष्ट बोला. स्थिर सूर बळी आणि इतर मदतनीसांना उपयोगी पडतो. ओरडू नका किंवा शब्द घाईघाईने बोलू नका.',
      'bridge_card_cancel': 'रद्द',
      'bridge_card_join_voice': 'व्हॉइसमध्ये सामील व्हा',
      'bridge_card_voice_connected': 'व्हॉइस कनेक्ट',
      'bridge_card_in_channel': 'चॅनेलमध्ये {n} जण',
      'bridge_card_transmitting': 'प्रसारण सुरू आहे…',
      'bridge_card_hold_to_talk': 'बोलण्यासाठी दाबून ठेवा',
      'bridge_card_disconnect': 'डिस्कनेक्ट',
      'vol_ems_banner_en_route': 'रुग्णवाहिका घटनास्थळाकडे',
      'vol_ems_banner_on_scene': 'रुग्णवाहिका स्थळी (~200 मी)',
      'vol_ems_banner_returning': 'रुग्णवाहिका रुग्णालयात परतत आहे',
      'vol_ems_banner_complete': 'प्रतिसाद पूर्ण · रुग्णवाहिका स्थानकावर',
      'vol_ems_banner_complete_with_cycle':
          'प्रतिसाद पूर्ण · रुग्णवाहिका स्थानकावर · एकूण चक्र {m}मि {s}से',
      'vol_tooltip_lifeline_first_aid':
          'लाइफलाइन — प्रथमोपचार मार्गदर्शक (प्रतिसादावर राहतो)',
      'vol_tooltip_exit_mission': 'मिशन सोडा',
      'vol_low_power_tracking_hint':
          'लो-पॉवर ट्रॅकिंग: आम्ही तुमची स्थिती कमी वेळा, मोठ्या हालचालींनंतरच सिंक करतो. डिस्पॅच तुमचा शेवटचा बिंदू पाहतो.',
      'vol_marker_you': 'तुम्ही',
      'vol_marker_active_unit': 'सक्रिय युनिट',
      'vol_marker_practice_incident': 'सराव घटना',
      'vol_marker_accident_scene': 'अपघात स्थळ',
      'vol_marker_training_pin': 'प्रशिक्षण पिन — खरा SOS नाही',
      'vol_marker_high_severity': 'GITM कॉलेज - उच्च तीव्रता',
      'vol_marker_accepted_hospital': 'स्वीकारले: {hospital}',
      'vol_marker_trying_hospital': 'प्रयत्न: {hospital}',
      'vol_marker_ambulance_on_scene': 'रुग्णवाहिका स्थळी!',
      'vol_marker_ambulance_en_route': 'रुग्णवाहिका मार्गावर',
      'vol_badge_at_scene_pin': 'स्थळ पिनवर',
      'vol_badge_in_5km_zone': '5 किमी क्षेत्रात',
      'vol_badge_en_route': 'मार्गावर',
    },

    // ── Gujarati (ગુજરાતી) ─────────────────────────────────────────────────
    'gu': {
      'app_name': 'EmergencyOS',
      'profile_title': 'પ્રોફાઇલ અને મેડિકલ આઈડી',
      'language': 'ભાષા',
      'save_medical_profile': 'મેડિકલ પ્રોફાઇલ સાચવો',
      'critical_medical_info': 'મહત્વની તબીબી માહિતી',
      'emergency_contacts': 'કટોકટી સંપર્કો',
      'golden_hour_details': 'ગોલ્ડન અવર વિગતો',
      'sos_lock': 'SOS લોક',
      'top_life_savers': 'ટોચના જીવનરક્ષકો',
      'lives_saved': 'બચાવેલા જીવ',
      'active_alerts': 'સક્રિય ચેતવણીઓ',
      'rank': 'રેન્ક',
      'on_duty': 'ફરજ પર',
      'standby': 'સ્ટેન્ડબાય',
      'sos': 'SOS',
      'call_now': 'હમણાં કૉલ કરો',
      'quick_guide': 'ઝડપી માર્ગદર્શિકા',
      'detailed_instructions': 'વિગતવાર સૂચનાઓ',
      'red_flags': 'જોખમના સંકેતો',
      'cautions': 'સાવચેતીઓ',
      'voice_walkthrough': 'વૉઇસ માર્ગદર્શન',
      'playing': 'ચાલુ છે...',
      'swipe_next_guide': 'આગળની માર્ગદર્શિકા માટે સ્વાઇપ કરો',
      'watch_video_guide': 'સંપૂર્ણ વીડિયો માર્ગદર્શિકા જુઓ',
      'emergency_grid_scan': 'કટોકટી ગ્રિડ સ્કેન',
      'area_telemetry': 'વિસ્તાર ટેલિમેટ્રી અને જોખમ સૂચકાંક',
      'report_hazard': 'જોખમ રિપોર્ટ કરો',
      'todays_duty': 'આજની ફરજ',
      'blood_type': 'લોહીનો પ્રકાર',
      'allergies': 'એલર્જી',
      'medical_conditions': 'તબીબી સ્થિતિ',
      'contact_name': 'પ્રાથમિક સંપર્ક નામ',
      'contact_phone': 'પ્રાથમિક સંપર્ક ફોન',
      'relationship': 'સંબંધ',
      'medications': 'વર્તમાન દવાઓ',
      'organ_donor': 'અંગ દાન સ્થિતિ',
      'good_morning': 'સુપ્રભાત,',
      'good_afternoon': 'શુભ બપોર,',
      'good_evening': 'શુભ સાંજ,',
      'hospitals': 'હોસ્પિટલો',
      'visual_walkthrough': 'દ્રશ્ય માર્ગદર્શન',
      'lifeline': 'લાઇફલાઇન',
      'nav_home': 'હોમ',
      'nav_map': 'નકશો',
      'nav_grid': 'ગ્રિડ',
      'nav_profile': 'પ્રોફાઇલ',
      'map_caching_offline_pct': 'ઑફલાઇન માટે વિસ્તાર કેશ થઈ રહ્યો છે — {pct}%',
      'map_drill_practice_banner':
          'અભ્યાસ ગ્રિડ: પલ્સિંગ પિન = ડેમો સક્રિય અલર્ટ્સ. પરતો માટે નકશા ફિલ્ટર — વાસ્તવિક ડેટા નહીં.',
      'map_recenter_tooltip': 'ફરીથી કેન્દ્રિત કરો',
      'map_legend_hospital': 'હોસ્પિટલ',
      'map_legend_live_sos_history': 'લાઇવ SOS / ઇતિહાસ',
      'map_legend_past_this_hex': 'ગત (આ હેક્સ)',
      'map_legend_in_area': 'વિસ્તારમાં {n}',
      'map_legend_in_cell': 'સેલમાં {n}',
      'map_legend_volunteers_on_duty': 'ડ્યુટી પર સ્વયંસેવકો',
      'map_legend_volunteers_in_grid': 'ગ્રિડમાં {n}',
      'map_legend_responder_scene': 'પ્રતિસાદ આપનાર → દૃશ્ય',
      'map_responder_routes_one': '{n} માર્ગ',
      'map_responder_routes_many': '{n} માર્ગો',
      'map_filters_title': 'નકશા ફિલ્ટર',
      'step_prefix': 'પગલું',
      'highlights_steps': 'એક એક કરીને પગલાં બતાવે છે',
      'offline_mode': 'ઓફલાઇન — નેટવર્ક ડિસ્કનેક્ટ',
      'volunteer': 'સ્વયંસેવક',
      'unranked': 'રેન્ક નથી',
      'live': 'લાઇવ',
      'you': 'તમે',
      'saved': 'બચાવ્યા',
      'xp_responses': 'XP · {0} પ્રતિભાવો',
      'duty_monitoring': 'તમે ફરજ પર હોવ ત્યારે SOS પોપ-અપ ચાલુ છે.',
      'turn_on_duty_msg': 'SOS પોપ-અપ મેળવવા માટે ફરજ ચાલુ કરો.',
      'on_duty_snack': 'ફરજ પર — તમારા વિસ્તારમાં ઘટનાઓનું નિરીક્ષણ...',
      'off_duty_snack': 'સ્ટેન્ડબાય — ફરજ સત્ર રેકોર્ડ થયું.',
      'leaderboard_offline': 'લીડરબોર્ડ ઓફલાઇન',
      'leaderboard_offline_sub': 'સિંક અટકી. કેશ્ડ સ્કોર.',
      'set_sos_pin_first': 'પહેલા SOS પિન સેટ કરો',
      'set_pin_safety_msg': 'સુરક્ષા માટે, SOS બનાવતા પહેલા પિન સેટ કરવો જરૂરી છે.',
      'set_pin_now': 'હમણાં પિન સેટ કરો',
      'later': 'પછી',
      'sos_are_you_conscious':
          'તમે સચેત છો? કૃપા કરીને હા અથવા ના જવાબ આપો.',
      'sos_tts_opening_guidance':
          'તમારું SOS સક્રિય છે. મદદ આવી રહી છે. બોલાતા સૂચનો અનુસરો અને જવાબ આપવા ટૅપ કરો.',
      'sos_interview_q1_prompt': 'શું થઈ રહ્યું છે? (કટોકટી પ્રકાર)',
      'sos_interview_q2_prompt': 'તમે સુરક્ષિત છો? કેટલું ગંભીર?',
      'sos_interview_q3_prompt': 'કેટલા લોકો સામેલ છે?',
      'sos_chip_cat_accident': 'અકસ્માત',
      'sos_chip_cat_medical': 'તબીબી',
      'sos_chip_cat_hazard': 'જોખમ (આગ, ડૂબવું વગેરે)',
      'sos_chip_cat_assault': 'હુમલો',
      'sos_chip_cat_other': 'અન્ય',
      'sos_chip_safe_critical': 'ગંભીર (જીવલેણ)',
      'sos_chip_safe_injured': 'ઇજા પણ સ્થિર',
      'sos_chip_safe_danger': 'ઇજા નહીં પણ જોખમમાં',
      'sos_chip_safe_safe_now': 'હવે સુરક્ષિત',
      'sos_chip_people_me': 'ફક્ત હું',
      'sos_chip_people_two': 'બે',
      'sos_chip_people_many': 'બે કરતાં વધુ',
      'sos_tts_interview_saved':
          'બધો ઇન્ટરવ્યૂ ડેટા સાચવ્યો. પ્રતિસાદકર્તાઓ પાસે વિગતો છે.',
      'sos_tts_map_routes':
          'નકશો ટૅબ ખોલો: લાલ સોંપેલ હોસ્પિટલનો રોડ માર્ગ અથવા નજીકનો માર્ગ; લીલો સ્વયંસેવક માર્ગ. કટોકટી અવાજ ચેનલ પર રહો.',
      'sos_tts_emergency_contacts_on_file':
          'Your emergency contact from your profile is attached to this SOS. SMS updates may be sent when that option is enabled.',
      'sos_tts_conscious_no_answer_attempt':
          'જવાબ નહીં. સચેત તપાસ {max} માંથી {n}. એક મિનિટ પછી ફરી પૂછીશું.',
      'voice_volunteer_accepted':
          'સ્વયંસેવકે સ્વીકાર્યું. મદદ માર્ગમાં છે.',
      'voice_ambulance_dispatched_eta':
          'એમ્બ્યુલન્સ મોકલી. અંદાજિત આગમન: {eta}.',
      'voice_police_dispatched_eta':
          'પોલીસ મોકલી. અંદાજિત આગમન: {eta}.',
      'voice_ambulance_on_scene_victim':
          'એમ્બ્યુલન્સ સ્થળ પર છે — તમથી લગભગ બસો મીટર દૂર.',
      'voice_ambulance_on_scene_volunteer':
          'એમ્બ્યુલન્સ સ્થળ પર છે — ઘટનાસ્થળથી લગભગ બસો મીટર અંદર.',
      'voice_ambulance_returning': 'એમ્બ્યુલન્સ હોસ્પિટલ તરફ પાછી ફરે છે.',
      'voice_response_complete_station':
          'પ્રતિસાદ પૂર્ણ. એમ્બ્યુલન્સ સ્ટેશન પર.',
      'voice_response_complete_cycle':
          'પ્રતિસાદ પૂર્ણ. એમ્બ્યુલન્સ સ્ટેશન પર. કુલ ચક્ર {minutes} મિનિટ {seconds} સેકંડ.',
      'voice_volunteers_on_scene_count':
          '{n} સ્વયંસેવકો હવે સ્થળ પર છે.',
      'voice_one_volunteer_on_scene': 'એક સ્વયંસેવક સ્થળ પર છે.',
      'voice_ptt_joined_comms': '{who} અવાજ સંચારમાં જોડાયા.',
      'voice_tts_unavailable_banner':
          'અવાજ માર્ગદર્શન ઉપલબ્ધ નથી — સ્ક્રીન પરનો લખાણ વાંચો.',
      'language_picker_title': 'ભાષા',
      'volunteer_victim_medical_card': 'પીડિત તબીબી કાર્ડ',
      'volunteer_dispatch_milestone_title': 'ડિસ્પેચ અપડેટ',
      'volunteer_dispatch_milestone_hospital': 'હોસ્પિટલ સ્વીકારી: {hospital}',
      'volunteer_dispatch_milestone_unit': 'એમ્બ્યુલન્સ યુનિટ: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'એમ્બ્યુલન્સ ક્રૂ: સંકલન…',
      'volunteer_dispatch_milestone_en_route': 'એમ્બ્યુલન્સ માર્ગ પર',
      'volunteer_triage_qr_report_title': 'QR અથવા ટૅપ રિપોર્ટ',
      'volunteer_triage_qr_report_subtitle':
          'હેન્ડઓફ માટે કોડ સ્કેન કરો અથવા ઘટનાનો રિપોર્ટ સાચવવા ટૅપ કરો.',
      'volunteer_triage_show_qr': 'QR બતાવો',
      'volunteer_triage_tap_report': 'રિપોર્ટ',
      'volunteer_triage_qr_title': 'ઘટના હેન્ડઓફ QR',
      'volunteer_triage_qr_body': 'રચનાત્મક ડેટા માટે સ્ટાફ અથવા EMS સાથે શેર કરો.',
      'volunteer_triage_report_saved': 'રિપોર્ટ આ ઘટના હેઠળ સાચવ્યો.',
      'volunteer_triage_report_failed': 'રિપોર્ટ સાચવી શકાયો નહીં: ',
      'volunteer_victim_medical_offline_hint': 'SOS પેકેટમાંથી — ઑફલાઇન કેશમાંથી.',
      'volunteer_victim_consciousness_title': 'સચેતતા',
      'volunteer_victim_three_questions': 'પ્રારંભિક જવાબો',
      'volunteer_major_updates_log': 'ફક્ત મુખ્ય અપડેટ',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'ટિયર {tier} સુધી વધારી રહ્યા છીએ. હોસ્પિટલ {hospital} પ્રયાસ કરી રહ્યા છીએ.',
      'volunteer_dispatch_trying_hospital': 'હોસ્પિટલ {hospital} પ્રયાસ કરી રહ્યા છીએ.',
      'volunteer_dispatch_hospital_accepted':
          '{hospital} એ કટોકટી સ્વીકારી. એમ્બ્યુલન્સ સંકલન ચાલુ છે.',
      'volunteer_dispatch_all_hospitals_notified':
          'બધી હોસ્પિટલોને જાણ કરી. કટોકટી સેવાઓ તરફ લઈ જઈ રહ્યા છીએ.',
      'sos_dispatch_alerting_nearest_trying':
          'તમારા વિસ્તારની નજીકની હોસ્પિટલને સૂચિત કરી રહ્યા છીએ. {hospital} પ્રયાસ કરી રહ્યા છીએ.',
      'sos_dispatch_escalating_tier_trying':
          'પ્રતિસાદ નહીં. ટિયર {tier} સુધી વધારી રહ્યા છીએ. {hospital} પ્રયાસ કરી રહ્યા છીએ.',
      'sos_dispatch_retry_previous_trying':
          'પાછલી હોસ્પિટલ પાસેથી પ્રતિસાદ નહીં. {hospital} પ્રયાસ કરી રહ્યા છીએ.',
      'sos_dispatch_all_hospitals_call_112':
          'બધી હોસ્પિટલોને જાણ કરી. કટોકટી સેવાઓ માટે કૃપા કરીને 112 કૉલ કરો.',
      'sos_active_title_big': 'સક્રિય SOS',
      'sos_active_help_coming': 'મદદ આવી રહી છે. શાંત રહો.',
      'sos_active_badge_waiting': 'પ્રતીક્ષા',
      'sos_active_badge_en_route_count': '{n} રસ્તામાં',
      'sos_active_mini_ambulance': 'એમ્બ્યુલન્સ',
      'sos_active_mini_on_scene': 'ઘટનાસ્થળે',
      'sos_active_mini_status': 'સ્થિતિ',
      'sos_active_volunteers_count_short': '{n} સ્વયંસેવકો',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title':
          'બધી હોસ્પિટલોને જાણ કરી',
      'sos_active_all_hospitals_notified_subtitle':
          'સમયસર કોઈ હોસ્પિટલે સ્વીકાર્યું નહીં. ડિસ્પેચ કટોકટી સેવાઓમાં વધારો કરી રહ્યું છે.',
      'sos_active_position_refresh_note':
          'બેટરી બચાવવા માટે SOS દરમિયાન તમારું સ્થાન લગભગ દર 45 સેકન્ડે અપડેટ થાય છે. એપ ખુલ્લી રાખો અને શક્ય હોય તો ચાર્જિંગમાં મૂકો.',
      'sos_active_mic_active': 'માઇક · સક્રિય',
      'sos_active_mic_active_detail':
          'લાઇવ ચેનલ તમારો માઇક્રોફોન મેળવી રહી છે.',
      'sos_active_mic_standby': 'માઇક · સ્ટેન્ડબાય',
      'sos_active_mic_standby_detail': 'વોઇસ ચેનલની રાહ…',
      'sos_active_mic_connecting': 'માઇક · કનેક્ટ થઈ રહ્યું',
      'sos_active_mic_connecting_detail':
          'કટોકટી વોઇસ ચેનલમાં જોડાઈ રહ્યું…',
      'sos_active_mic_reconnecting': 'માઇક · ફરીથી કનેક્ટ',
      'sos_active_mic_reconnecting_detail':
          'લાઇવ ઑડિયો પુનઃસ્થાપિત કરી રહ્યું…',
      'sos_active_mic_failed': 'માઇક · વિક્ષેપ',
      'sos_active_mic_failed_detail':
          'વોઇસ ચેનલ ઉપલબ્ધ નથી. ઉપર RETRY વાપરો.',
      'sos_active_mic_ptt_only': 'માઇક · ઘટના ચેનલ',
      'sos_active_mic_ptt_only_detail':
          'ઓપરેશન્સ કન્સોલે Firebase PTT દ્વારા અવાજ રૂટ કર્યો. જવાબ આપનારને પહોંચવા બ્રોડકાસ્ટ દબાવી રાખો.',
      'sos_active_mic_interrupted': 'માઇક · વિરામિત',
      'sos_active_mic_interrupted_detail':
          'એપ ઑડિયો પ્રોસેસ કરે ત્યારે થોડો વિરામ.',
      'sos_active_consciousness_note':
          'ચેતના તપાસોના જવાબ હા કે ના માં આપો; અન્ય પ્રોમ્પ્ટ સ્ક્રીન વિકલ્પો વાપરે છે.',
      'sos_active_live_updates_header': 'લાઇવ અપડેટ્સ',
      'sos_active_live_updates_subtitle':
          'ડિસ્પેચ, સ્વયંસેવકો અને ઉપકરણ',
      'sos_active_live_tag': 'લાઇવ',
      'sos_active_activity_log': 'પ્રવૃત્તિ લોગ',
      'sos_active_header_stat_coordinating_crew': 'ટીમ સંકલન',
      'sos_active_header_stat_coordinating': 'સંકલન',
      'sos_active_header_stat_en_route': 'રસ્તે',
      'sos_active_header_stat_route_min': '~{n} મિનિટ',
      'sos_active_live_sos_is_live_title': 'SOS લાઇવ છે',
      'sos_active_live_sos_is_live_detail':
          'તમારું સ્થાન અને તબીબી ફ્લેગ કટોકટી નેટવર્ક પર છે.',
      'sos_active_live_volunteers_notified_title':
          'સ્વયંસેવકોને જાણ',
      'sos_active_live_volunteers_notified_detail':
          'નજીકના સ્વયંસેવકોને આ ઘટના રિયલ ટાઇમમાં મળે છે.',
      'sos_active_live_bridge_connected_title':
          'કટોકટી વોઇસ બ્રિજ કનેક્ટ',
      'sos_active_live_bridge_connected_detail':
          'ડિસ્પેચ ડેસ્ક અને જવાબ આપનારા આ ચેનલ સાંભળી શકે છે.',
      'sos_active_live_ptt_title': 'Firebase PTT દ્વારા અવાજ',
      'sos_active_live_ptt_detail':
          'આ ફ્લીટ માટે લાઇવ WebRTC બ્રિજ બંધ છે. અવાજ અને ટેક્સ્ટ અપડેટ્સ માટે બ્રોડકાસ્ટ વાપરો.',
      'sos_active_live_contacts_notified_title':
          'કટોકટી સંપર્કોને જાણ',
      'sos_active_live_hospital_accepted_title': 'હોસ્પિટલે સ્વીકાર્યું',
      'sos_active_live_ambulance_unit_assigned_title':
          'એમ્બ્યુલન્સ એકમ નિયુક્ત',
      'sos_active_live_ambulance_unit_assigned_subtitle': 'એકમ {unit}',
      'sos_active_live_ambulance_en_route_title': 'એમ્બ્યુલન્સ રસ્તામાં',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'રસ્તામાં',
      'sos_active_live_ambulance_en_route_route_eta': '~{n} મિનિટ (માર્ગ)',
      'sos_active_live_ambulance_coordination_title': 'એમ્બ્યુલન્સ સંકલન',
      'sos_active_live_ambulance_coordination_pending':
          'હોસ્પિટલે સ્વીકાર્યું — એમ્બ્યુલન્સ ઓપરેટરોને જાણ થઈ રહી છે.',
      'sos_active_live_ambulance_coordination_arranging':
          'એમ્બ્યુલન્સ ક્રૂ વ્યવસ્થા — એકમ રસ્તામાં હોય ત્યારે મિનિટ ETA.',
      'sos_active_live_responder_status_title': 'જવાબ આપનાર સ્થિતિ',
      'sos_active_live_volunteer_accepted_single_title':
          'સ્વયંસેવક સ્વીકાર્યું',
      'sos_active_live_volunteer_accepted_many_title':
          'સ્વયંસેવકોએ સ્વીકાર્યું',
      'sos_active_live_volunteer_accepted_single_detail':
          'એક જવાબ આપનાર નિયુક્ત છે અને તમારી તરફ આવી રહ્યા છે.',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} જવાબ આપનારા આ SOS માટે નિયુક્ત છે.',
      'sos_active_live_volunteer_on_scene_single_title':
          'સ્વયંસેવક ઘટનાસ્થળે પહોંચ્યા',
      'sos_active_live_volunteer_on_scene_many_title':
          'સ્વયંસેવકો ઘટનાસ્થળે',
      'sos_active_live_volunteer_on_scene_single_detail':
          'કોઈ તમારી સાથે અથવા તમારા પિન પર છે.',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} જવાબ આપનારા ઘટનાસ્થળે નોંધાયેલા.',
      'sos_active_live_responder_location_title':
          'લાઇવ જવાબ આપનાર સ્થાન',
      'sos_active_live_responder_location_detail':
          'નિયુક્ત સ્વયંસેવકનો GPS નકશા પર અપડેટ થઈ રહ્યો છે.',
      'sos_active_live_professional_dispatch_title':
          'વ્યાવસાયિક ડિસ્પેચ સક્રિય',
      'sos_active_live_professional_dispatch_detail':
          'સંકલિત સેવાઓ આ ઘટના પર કામ કરી રહી છે.',
      'sos_active_ambulance_200m_detail':
          'એમ્બ્યુલન્સ ઘટનાસ્થળે — લગભગ 200 મીટરની અંદર.',
      'sos_active_ambulance_200m_semantic_label':
          'એમ્બ્યુલન્સ લગભગ બસો મીટરની અંદર ઘટનાસ્થળે',
      'sos_active_bridge_channel_on_suffix': ' · {n} ચેનલ પર',
      'sos_active_bridge_channel_voice': 'કટોકટી વોઇસ ચેનલ',
      'sos_active_bridge_channel_ptt': 'કટોકટી ચેનલ · Firebase PTT',
      'sos_active_bridge_channel_failed':
          'કટોકટી ચેનલ · ફરીથી પ્રયાસ કરો',
      'sos_active_bridge_channel_connecting':
          'કટોકટી ચેનલ · કનેક્ટ થઈ રહ્યું',
      'sos_active_dispatch_contact_hospitals_default':
          'તમારા સ્થાન અને કટોકટીના પ્રકાર આધારે અમે નજીકની હોસ્પિટલોનો સંપર્ક કરી રહ્યા છીએ.',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'એમ્બ્યુલન્સ ક્રૂને જાણ',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'પાર્ટનર હોસ્પિટલે તમારો કેસ સ્વીકાર્યો. એમ્બ્યુલન્સ ઓપરેટરોને જાણ થઈ રહી છે.',
      'sos_active_dispatch_ambulance_confirmed_title': 'એમ્બ્યુલન્સ પુષ્ટિ',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'એકમ {unit} તમારી તરફ આવી રહ્યું છે. જ્યાં જવાબ આપનારા પહોંચી શકે ત્યાં રહો.',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'એક એમ્બ્યુલન્સ તમારી તરફ આવી રહી છે. જ્યાં જવાબ આપનારા પહોંચી શકે ત્યાં રહો.',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'એમ્બ્યુલન્સ હસ્તાંતરણ વિલંબ',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'હોસ્પિટલે સ્વીકાર્યું, પણ સમયસર કોઈ એમ્બ્યુલન્સ ક્રૂએ પુષ્ટિ કરી નહીં. ડિસ્પેચ વધારી રહ્યું છે — જરૂર હોય તો 112 પર કૉલ કરો.',
      'sos_active_dispatch_pending_title_trying': 'પ્રયાસ: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · હોસ્પિટલ જવાબની રાહ.',
      'sos_active_dispatch_accepted_title': '{hospital} એ સ્વીકાર્યું',
      'sos_active_dispatch_accepted_subtitle':
          'એમ્બ્યુલન્સ ડિસ્પેચનું સંકલન થઈ રહ્યું છે.',
      'sos_active_dispatch_exhausted_title':
          'બધી હોસ્પિટલોને જાણ',
      'sos_active_dispatch_exhausted_subtitle':
          'સમયસર કોઈ હોસ્પિટલે સ્વીકાર્યું નહીં. ડિસ્પેચ કટોકટી સેવાઓમાં વધારો કરી રહ્યું છે.',
      'sos_active_dispatch_generic_title': 'હોસ્પિટલ ડિસ્પેચ',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'કટોકટી વોઇસ ચેનલ',
      'volunteer_bridge_join_hint_incident':
          'જોડાવા માટે આ ઘટનાનો ઉપયોગ થાય છે: તમારો નંબર મેળ ખાતો હોય તો કટોકટી સંપર્ક; અન્યથા સ્વીકૃત સ્વયંસેવક.',
      'volunteer_bridge_join_hint_elite':
          'તમે સ્વીકૃત જવાબ આપનાર હો ત્યારે જોડાણ તમારા એલિટ પ્રવેશનો ઉપયોગ કરે છે; અન્યથા નંબર મેળ ખાય તો સંપર્ક.',
      'volunteer_bridge_join_hint_desk':
          'તમારી પ્રોફાઇલ પરની કટોકટી સેવાઓ ડેસ્ક તરીકે તમે ડિસ્પેચ તરીકે જોડાઓ છો.',
      'volunteer_bridge_join_voice_btn': 'વોઇસમાં જોડાઓ',
      'volunteer_bridge_connecting_btn': 'કનેક્ટ થઈ રહ્યું…',
      'volunteer_bridge_incident_id_hint': 'ઘટના ID',
      'volunteer_consignment_live_location_hint':
          'તમે કન્સાઇનમેન્ટ પર હો ત્યારે, નકશા અને ETA સચોટ રાખવા તમારું લાઇવ સ્થાન આ ઘટના સાથે શેર થાય છે.',
      'volunteer_consignment_low_power_label': 'લો પાવર',
      'volunteer_consignment_normal_gps_label': 'સામાન્ય GPS',
      'bridge_card_incident_id_missing': 'ઘટના ID ગુમ છે.',
      'bridge_card_ptt_only_snackbar':
          'ઓપરેશન કોન્સોલે ભોગ બનનારનો અવાજ Firebase PTT મારફતે મોકલ્યો. WebRTC બ્રિજ જોડાણ નિષ્ક્રિય.',
      'bridge_card_ptt_only_banner':
          'કોન્સોલે Firebase PTT મારફતે અવાજ મોકલ્યો — આ ફ્લીટ માટે LiveKit બ્રિજ જોડાણ નિષ્ક્રિય.',
      'bridge_card_connected_snackbar': 'વોઇસ ચેનલ સાથે જોડાયા.',
      'bridge_card_could_not_join': 'જોડાઈ શકાયું નહીં: {err}',
      'bridge_card_voice_channel_title': 'વોઇસ ચેનલ',
      'bridge_card_calm_disclaimer':
          'શાંત રહો અને સ્પષ્ટ બોલો. સ્થિર સ્વર ભોગ બનનાર અને અન્ય સહાયકોને મદદ કરે છે. ચીસો ન પાડો કે શબ્દો ઉતાવળે બોલશો નહીં.',
      'bridge_card_cancel': 'રદ',
      'bridge_card_join_voice': 'વોઇસમાં જોડાઓ',
      'bridge_card_voice_connected': 'વોઇસ જોડાયેલ',
      'bridge_card_in_channel': 'ચેનલમાં {n} જણ',
      'bridge_card_transmitting': 'પ્રસારણ થઈ રહ્યું છે…',
      'bridge_card_hold_to_talk': 'બોલવા માટે પકડી રાખો',
      'bridge_card_disconnect': 'ડિસ્કનેક્ટ',
      'vol_ems_banner_en_route': 'એમ્બ્યુલન્સ ઘટનાસ્થળ તરફ',
      'vol_ems_banner_on_scene': 'એમ્બ્યુલન્સ સ્થળે (~200 મી)',
      'vol_ems_banner_returning': 'એમ્બ્યુલન્સ હોસ્પિટલ પરત આવી રહી છે',
      'vol_ems_banner_complete': 'પ્રતિસાદ પૂર્ણ · એમ્બ્યુલન્સ સ્ટેશન પર',
      'vol_ems_banner_complete_with_cycle':
          'પ્રતિસાદ પૂર્ણ · એમ્બ્યુલન્સ સ્ટેશન પર · કુલ ચક્ર {m}મિ {s}સે',
      'vol_tooltip_lifeline_first_aid':
          'લાઇફલાઇન — પ્રાથમિક ઉપચાર માર્ગદર્શિકા (પ્રતિસાદ પર રહે છે)',
      'vol_tooltip_exit_mission': 'મિશન છોડો',
      'vol_low_power_tracking_hint':
          'લો-પાવર ટ્રેકિંગ: અમે તમારી સ્થિતિ ઓછી વખત, મોટી હલનચલન પછી જ સિંક કરીએ છીએ. ડિસ્પેચ તમારો છેલ્લો બિંદુ જુએ છે.',
      'vol_marker_you': 'તમે',
      'vol_marker_active_unit': 'સક્રિય એકમ',
      'vol_marker_practice_incident': 'અભ્યાસ ઘટના',
      'vol_marker_accident_scene': 'અકસ્માત સ્થળ',
      'vol_marker_training_pin': 'તાલીમ પિન — સાચો SOS નથી',
      'vol_marker_high_severity': 'GITM કોલેજ - ઉચ્ચ ગંભીરતા',
      'vol_marker_accepted_hospital': 'સ્વીકાર્યું: {hospital}',
      'vol_marker_trying_hospital': 'પ્રયત્ન: {hospital}',
      'vol_marker_ambulance_on_scene': 'એમ્બ્યુલન્સ સ્થળે!',
      'vol_marker_ambulance_en_route': 'એમ્બ્યુલન્સ રસ્તે',
      'vol_badge_at_scene_pin': 'સ્થળ પિન પર',
      'vol_badge_in_5km_zone': '5 કિમી વિસ્તારમાં',
      'vol_badge_en_route': 'રસ્તે',
    },

    // ── Punjabi (ਪੰਜਾਬੀ) ──────────────────────────────────────────────────
    'pa': {
      'app_name': 'EmergencyOS',
      'profile_title': 'ਪ੍ਰੋਫਾਈਲ ਅਤੇ ਮੈਡੀਕਲ ਆਈਡੀ',
      'language': 'ਭਾਸ਼ਾ',
      'save_medical_profile': 'ਮੈਡੀਕਲ ਪ੍ਰੋਫਾਈਲ ਸੇਵ ਕਰੋ',
      'critical_medical_info': 'ਮਹੱਤਵਪੂਰਨ ਡਾਕਟਰੀ ਜਾਣਕਾਰੀ',
      'emergency_contacts': 'ਐਮਰਜੈਂਸੀ ਸੰਪਰਕ',
      'golden_hour_details': 'ਗੋਲਡਨ ਅਵਰ ਵੇਰਵੇ',
      'sos_lock': 'SOS ਲਾਕ',
      'top_life_savers': 'ਸਿਖਰਲੇ ਜੀਵਨ ਰੱਖਿਅਕ',
      'lives_saved': 'ਬਚਾਈਆਂ ਜਾਨਾਂ',
      'active_alerts': 'ਕਿਰਿਆਸ਼ੀਲ ਚੇਤਾਵਨੀਆਂ',
      'rank': 'ਰੈਂਕ',
      'on_duty': 'ਡਿਊਟੀ ਤੇ',
      'standby': 'ਸਟੈਂਡਬਾਈ',
      'sos': 'SOS',
      'call_now': 'ਹੁਣੇ ਕਾਲ ਕਰੋ',
      'quick_guide': 'ਤੇਜ਼ ਗਾਈਡ',
      'detailed_instructions': 'ਵਿਸਤ੍ਰਿਤ ਹਿਦਾਇਤਾਂ',
      'red_flags': 'ਖ਼ਤਰੇ ਦੇ ਸੰਕੇਤ',
      'cautions': 'ਸਾਵਧਾਨੀਆਂ',
      'voice_walkthrough': 'ਵੌਇਸ ਗਾਈਡ',
      'playing': 'ਚੱਲ ਰਿਹਾ ਹੈ...',
      'swipe_next_guide': 'ਅਗਲੀ ਗਾਈਡ ਲਈ ਸਵਾਈਪ ਕਰੋ',
      'watch_video_guide': 'ਪੂਰੀ ਵੀਡੀਓ ਗਾਈਡ ਦੇਖੋ',
      'emergency_grid_scan': 'ਐਮਰਜੈਂਸੀ ਗਰਿੱਡ ਸਕੈਨ',
      'area_telemetry': 'ਖੇਤਰ ਟੈਲੀਮੈਟਰੀ ਅਤੇ ਖ਼ਤਰਾ ਸੂਚਕ',
      'report_hazard': 'ਖ਼ਤਰੇ ਦੀ ਰਿਪੋਰਟ ਕਰੋ',
      'todays_duty': 'ਅੱਜ ਦੀ ਡਿਊਟੀ',
      'blood_type': 'ਖ਼ੂਨ ਦਾ ਗਰੁੱਪ',
      'allergies': 'ਐਲਰਜੀ',
      'medical_conditions': 'ਡਾਕਟਰੀ ਸਥਿਤੀ',
      'contact_name': 'ਮੁੱਖ ਸੰਪਰਕ ਨਾਮ',
      'contact_phone': 'ਮੁੱਖ ਸੰਪਰਕ ਫ਼ੋਨ',
      'relationship': 'ਰਿਸ਼ਤਾ',
      'medications': 'ਮੌਜੂਦਾ ਦਵਾਈਆਂ',
      'organ_donor': 'ਅੰਗ ਦਾਨ ਸਥਿਤੀ',
      'good_morning': 'ਸ਼ੁਭ ਸਵੇਰ,',
      'good_afternoon': 'ਸ਼ੁਭ ਦੁਪਹਿਰ,',
      'good_evening': 'ਸ਼ੁਭ ਸ਼ਾਮ,',
      'hospitals': 'ਹਸਪਤਾਲ',
      'visual_walkthrough': 'ਵਿਜ਼ੂਅਲ ਗਾਈਡ',
      'lifeline': 'ਲਾਈਫ਼ਲਾਈਨ',
      'nav_home': 'ਘਰ',
      'nav_map': 'ਨਕਸ਼ਾ',
      'nav_grid': 'ਗ੍ਰਿਡ',
      'nav_profile': 'ਪ੍ਰੋਫ਼ਾਈਲ',
      'map_caching_offline_pct': 'ਔਫਲਾਈਨ ਲਈ ਖੇਤਰ ਕੈਸ਼ ਹੋ ਰਿਹਾ ਹੈ — {pct}%',
      'map_drill_practice_banner':
          'ਅਭਿਆਸ ਗ੍ਰਿਡ: ਪਲਸਿੰਗ ਪਿੰਨ = ਡੈਮੋ ਸਰਗਰਮ ਅਲਰਟ। ਪਰਤਾਂ ਲਈ ਨਕਸ਼ਾ ਫਿਲਟਰ — ਅਸਲ ਡਾਟਾ ਨਹੀਂ।',
      'map_recenter_tooltip': 'ਮੁੜ ਕੇਂਦਰਿਤ ਕਰੋ',
      'map_legend_hospital': 'ਹਸਪਤਾਲ',
      'map_legend_live_sos_history': 'ਲਾਈਵ SOS / ਇਤਿਹਾਸ',
      'map_legend_past_this_hex': 'ਪਿਛਲਾ (ਇਹ ਹੈਕਸ)',
      'map_legend_in_area': 'ਖੇਤਰ ਵਿੱਚ {n}',
      'map_legend_in_cell': 'ਸੈਲ ਵਿੱਚ {n}',
      'map_legend_volunteers_on_duty': 'ਡਿਊਟੀ \'ਤੇ ਸਵੈਇੱਛਕ',
      'map_legend_volunteers_in_grid': 'ਗ੍ਰਿਡ ਵਿੱਚ {n}',
      'map_legend_responder_scene': 'ਜਵਾਬਦੇਹ → ਦ੍ਰਿਸ਼',
      'map_responder_routes_one': '{n} ਰਸਤਾ',
      'map_responder_routes_many': '{n} ਰਸਤੇ',
      'map_filters_title': 'ਨਕਸ਼ਾ ਫਿਲਟਰ',
      'step_prefix': 'ਕਦਮ',
      'highlights_steps': 'ਇੱਕ-ਇੱਕ ਕਰਕੇ ਕਦਮ ਦਿਖਾਉਂਦਾ ਹੈ',
      'offline_mode': 'ਆਫ਼ਲਾਈਨ — ਨੈੱਟਵਰਕ ਕੱਟਿਆ',
      'volunteer': 'ਵਲੰਟੀਅਰ',
      'unranked': 'ਰੈਂਕ ਨਹੀਂ',
      'live': 'ਲਾਈਵ',
      'you': 'ਤੁਸੀਂ',
      'saved': 'ਬਚਾਏ',
      'xp_responses': 'XP · {0} ਜਵਾਬ',
      'duty_monitoring': 'ਜਦੋਂ ਤੁਸੀਂ ਡਿਊਟੀ ਤੇ ਹੋ SOS ਪੌਪ-ਅੱਪ ਚਾਲੂ ਹਨ।',
      'turn_on_duty_msg': 'SOS ਪੌਪ-ਅੱਪ ਪ੍ਰਾਪਤ ਕਰਨ ਲਈ ਡਿਊਟੀ ਚਾਲੂ ਕਰੋ।',
      'on_duty_snack': 'ਡਿਊਟੀ ਤੇ — ਤੁਹਾਡੇ ਖੇਤਰ ਵਿੱਚ ਘਟਨਾਵਾਂ ਦੀ ਨਿਗਰਾਨੀ...',
      'off_duty_snack': 'ਸਟੈਂਡਬਾਈ — ਡਿਊਟੀ ਸੈਸ਼ਨ ਰਿਕਾਰਡ ਕੀਤਾ।',
      'leaderboard_offline': 'ਲੀਡਰਬੋਰਡ ਆਫ਼ਲਾਈਨ',
      'leaderboard_offline_sub': 'ਸਿੰਕ ਰੁਕੀ। ਕੈਸ਼ ਸਕੋਰ।',
      'set_sos_pin_first': 'ਪਹਿਲਾਂ SOS ਪਿੰਨ ਸੈੱਟ ਕਰੋ',
      'set_pin_safety_msg': 'ਸੁਰੱਖਿਆ ਲਈ, SOS ਬਣਾਉਣ ਤੋਂ ਪਹਿਲਾਂ ਪਿੰਨ ਸੈੱਟ ਕਰਨਾ ਜ਼ਰੂਰੀ ਹੈ।',
      'set_pin_now': 'ਹੁਣੇ ਪਿੰਨ ਸੈੱਟ ਕਰੋ',
      'later': 'ਬਾਅਦ ਵਿੱਚ',
      'sos_are_you_conscious':
          'ਕੀ ਤੁਸੀਂ ਹੋਸ਼ ਵਿੱਚ ਹੋ? ਕਿਰਪਾ ਕਰਕੇ ਹਾਂ ਜਾਂ ਨਾਂ ਜਵਾਬ ਦਿਓ।',
      'sos_tts_opening_guidance':
          'ਤੁਹਾਡਾ SOS ਸਰਗਰਮ ਹੈ। ਮਦਦ ਆ ਰਹੀ ਹੈ। ਬੋਲੇ ਗਏ ਨਿਰਦੇਸ਼ਾਂ ਦੀ ਪਾਲਣਾ ਕਰੋ ਅਤੇ ਜਵਾਬ ਦੇਣ ਲਈ ਟੈਪ ਕਰੋ।',
      'sos_interview_q1_prompt': 'ਕੀ ਹੋ ਰਿਹਾ ਹੈ? (ਐਮਰਜੈਂਸੀ ਕਿਸਮ)',
      'sos_interview_q2_prompt': 'ਕੀ ਤੁਸੀਂ ਸੁਰੱਖਿਤ ਹੋ? ਕਿੰਨਾ ਗੰਭੀਰ?',
      'sos_interview_q3_prompt': 'ਕਿੰਨੇ ਲੋਕ ਸ਼ਾਮਲ ਹਨ?',
      'sos_chip_cat_accident': 'ਦੁਰਘਟਨਾ',
      'sos_chip_cat_medical': 'ਤਬੀਬੀ',
      'sos_chip_cat_hazard': 'ਖਤਰਾ (ਅੱਗ, ਡੁੱਬਣਾ ਆਦਿ)',
      'sos_chip_cat_assault': 'ਹਮਲਾ',
      'sos_chip_cat_other': 'ਹੋਰ',
      'sos_chip_safe_critical': 'ਗੰਭੀਰ (ਜਾਨਲੇਵਾ)',
      'sos_chip_safe_injured': 'ਜ਼ਖਮੀ ਪਰ ਸਥਿਰ',
      'sos_chip_safe_danger': 'ਜ਼ਖਮੀ ਨਹੀਂ ਪਰ ਖਤਰੇ ਵਿੱਚ',
      'sos_chip_safe_safe_now': 'ਹੁਣ ਸੁਰੱਖਿਤ',
      'sos_chip_people_me': 'ਸਿਰਫ ਮੈਂ',
      'sos_chip_people_two': 'ਦੋ',
      'sos_chip_people_many': 'ਦੋ ਤੋਂ ਵੱਧ',
      'sos_tts_interview_saved':
          'ਸਾਰਾ ਇੰਟਰਵਿਊ ਡੇਟਾ ਸੁਰੱਖਿਤ। ਜਵਾਬਦੇਹਾਂ ਕੋਲ ਵਿਸਤਾਰ ਹੈ।',
      'sos_tts_map_routes':
          'ਨਕਸ਼ਾ ਟੈਬ ਖੋਲ੍ਹੋ: ਲਾਲ ਨਿਯੁਕਤ ਹਸਪਤਾਲ ਦਾ ਸੜਕ ਰਸਤਾ ਜਾਂ ਨੇੜੇ ਦਾ ਰਸਤਾ; ਹਰਾ ਸਵੈਸੇਵਕ ਰਸਤਾ। ਐਮਰਜੈਂਸੀ ਵੌਇਸ ਚੈਨਲ ਤੇ ਰਹੋ।',
      'sos_tts_emergency_contacts_on_file':
          'Your emergency contact from your profile is attached to this SOS. SMS updates may be sent when that option is enabled.',
      'sos_tts_conscious_no_answer_attempt':
          'ਕੋਈ ਜਵਾਬ ਨਹੀਂ। ਹੋਸ਼ ਜਾਂਚ {max} ਵਿੱਚੋਂ {n}। ਇੱਕ ਮਿੰਟ ਬਾਅਦ ਫਿਰ ਪੁੱਛਾਂਗੇ।',
      'voice_volunteer_accepted':
          'ਸਵੈਇਚ্ছਕ ਨੇ ਮਨਜ਼ੂਰ ਕੀਤਾ। ਮਦਦ ਰਾਹ ਵਿੱਚ ਹੈ।',
      'voice_ambulance_dispatched_eta':
          'ਐਂਬੂਲੈਂਸ ਭੇਜੀ ਗਈ। ਅਨੁਮਾਨਿਤ ਆਗਮਨ: {eta}।',
      'voice_police_dispatched_eta':
          'ਪੁਲਿਸ ਭੇਜੀ ਗਈ। ਅਨੁਮਾਨਿਤ ਆਗਮਨ: {eta}।',
      'voice_ambulance_on_scene_victim':
          'ਐਂਬੂਲੈਂਸ ਮੌਕੇ ਤੇ ਹੈ — ਤੁਹਾਡੇ ਤੋਂ ਲਗਭਗ ਦੋ ਸੌ ਮੀਟਰ ਦੂਰ।',
      'voice_ambulance_on_scene_volunteer':
          'ਐਂਬੂਲੈਂਸ ਮੌਕੇ ਤੇ ਹੈ — ਘਟਨਾ ਸਥਾਨ ਤੋਂ ਲਗਭਗ ਦੋ ਸੌ ਮੀਟਰ ਦੇ ਅੰਦਰ।',
      'voice_ambulance_returning': 'ਐਂਬੂਲੈਂਸ ਹਸਪਤਾਲ ਵੱਲ ਵਾਪਸ ਜਾ ਰਹੀ ਹੈ।',
      'voice_response_complete_station':
          'ਜਵਾਬ ਪੂਰਾ। ਐਂਬੂਲੈਂਸ ਸਟੇਸ਼ਨ ਤੇ।',
      'voice_response_complete_cycle':
          'ਜਵਾਬ ਪੂਰਾ। ਐਂਬੂਲੈਂਸ ਸਟੇਸ਼ਨ ਤੇ। ਕੁੱਲ ਚੱਕਰ {minutes} ਮਿੰਟ {seconds} ਸਕਿੰਟ।',
      'voice_volunteers_on_scene_count':
          '{n} ਸਵੈਇਚ্ছਕ ਹੁਣ ਮੌਕੇ ਤੇ ਹਨ।',
      'voice_one_volunteer_on_scene': 'ਇੱਕ ਵਲੰਟੀਅਰ ਮੌਕੇ ਤੇ ਹੈ।',
      'voice_ptt_joined_comms': '{who} ਆਵਾਜ਼ ਸੰਚਾਰ ਵਿੱਚ ਸ਼ਾਮਲ ਹੋਏ।',
      'voice_tts_unavailable_banner':
          'ਆਵਾਜ਼ ਮਾਰਗਦਰਸ਼ਨ ਉਪਲਬਧ ਨਹੀਂ — ਸਕ੍ਰੀਨ ਤੇ ਲਿਖਤ ਪੜ੍ਹੋ।',
      'language_picker_title': 'ਭਾਸ਼ਾ',
      'volunteer_victim_medical_card': 'ਪੀੜਤ ਮੈਡੀਕਲ ਕਾਰਡ',
      'volunteer_dispatch_milestone_title': 'ਡਿਸਪੈਚ ਅੱਪਡੇਟ',
      'volunteer_dispatch_milestone_hospital': 'ਹਸਪਤਾਲ ਨੇ ਸਵੀਕਾਰ ਕੀਤਾ: {hospital}',
      'volunteer_dispatch_milestone_unit': 'ਐਂਬੂਲੈਂਸ ਯੂਨਿਟ: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'ਐਂਬੂਲੈਂਸ ਕਰੂ: ਤਾਲਮੇਲ…',
      'volunteer_dispatch_milestone_en_route': 'ਐਂਬੂਲੈਂਸ ਰਸਤੇ ਵਿੱਚ',
      'volunteer_triage_qr_report_title': 'QR ਜਾਂ ਟੈਪ ਰਿਪੋਰਟ',
      'volunteer_triage_qr_report_subtitle':
          'ਹੈਂਡਆਫ ਲਈ ਕੋਡ ਸਕੈਨ ਕਰੋ ਜਾਂ ਘਟਨਾ ਰਿਪੋਰਟ ਸੇਵ ਕਰਨ ਲਈ ਟੈਪ ਕਰੋ।',
      'volunteer_triage_show_qr': 'QR ਦਿਖਾਓ',
      'volunteer_triage_tap_report': 'ਰਿਪੋਰਟ',
      'volunteer_triage_qr_title': 'ਘਟਨਾ ਹੈਂਡਆਫ QR',
      'volunteer_triage_qr_body': 'ਸਟਰਕਚਰਡ ਡੇਟਾ ਲਈ ਸਟਾਫ ਜਾਂ EMS ਨਾਲ ਸਾਂਝਾ ਕਰੋ।',
      'volunteer_triage_report_saved': 'ਰਿਪੋਰਟ ਇਸ ਘਟਨਾ ਹੇਠ ਸੇਵ ਹੋਈ।',
      'volunteer_triage_report_failed': 'ਰਿਪੋਰਟ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕੀ: ',
      'volunteer_victim_medical_offline_hint': 'SOS ਪੈਕੇਟ ਤੋਂ — ਔਫਲਾਈਨ ਕੈਸ਼ ਤੋਂ।',
      'volunteer_victim_consciousness_title': 'ਹੋਸ਼',
      'volunteer_victim_three_questions': 'ਸ਼ੁਰੂਆਤੀ ਜਵਾਬ',
      'volunteer_major_updates_log': 'ਸਿਰਫ਼ ਮੁੱਖ ਅੱਪਡੇਟ',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'ਟੀਅਰ {tier} ਤੱਕ ਵਧਾ ਰਹੇ ਹਾਂ। ਹਸਪਤਾਲ {hospital} ਕੋਸ਼ਿਸ਼ ਕਰ ਰਹੇ ਹਾਂ।',
      'volunteer_dispatch_trying_hospital': 'ਹਸਪਤਾਲ {hospital} ਕੋਸ਼ਿਸ਼ ਕਰ ਰਹੇ ਹਾਂ।',
      'volunteer_dispatch_hospital_accepted':
          '{hospital} ਨੇ ਐਮਰਜੈਂਸੀ ਸਵੀਕਾਰ ਕੀਤੀ। ਐਂਬੂਲੈਂਸ ਤਾਲਮੇਲ ਜਾਰੀ ਹੈ।',
      'volunteer_dispatch_all_hospitals_notified':
          'ਸਾਰੇ ਹਸਪਤਾਲਾਂ ਨੂੰ ਸੂਚਿਤ ਕੀਤਾ। ਐਮਰਜੈਂਸੀ ਸੇਵਾਵਾਂ ਵੱਲ ਭੇਜ ਰਹੇ ਹਾਂ।',
      'sos_dispatch_alerting_nearest_trying':
          'ਤੁਹਾਡੇ ਖੇਤਰ ਦੇ ਨੇੜਲੇ ਹਸਪਤਾਲ ਨੂੰ ਅਲਰਟ ਕਰ ਰਹੇ ਹਾਂ। {hospital} ਕੋਸ਼ਿਸ਼ ਕਰ ਰਹੇ ਹਾਂ।',
      'sos_dispatch_escalating_tier_trying':
          'ਕੋਈ ਜਵਾਬ ਨਹੀਂ। ਟੀਅਰ {tier} ਤੱਕ ਵਧਾ ਰਹੇ ਹਾਂ। {hospital} ਕੋਸ਼ਿਸ਼ ਕਰ ਰਹੇ ਹਾਂ।',
      'sos_dispatch_retry_previous_trying':
          'ਪਿਛਲੇ ਹਸਪਤਾਲ ਤੋਂ ਕੋਈ ਜਵਾਬ ਨਹੀਂ। {hospital} ਕੋਸ਼ਿਸ਼ ਕਰ ਰਹੇ ਹਾਂ।',
      'sos_dispatch_all_hospitals_call_112':
          'ਸਾਰੇ ਹਸਪਤਾਲਾਂ ਨੂੰ ਸੂਚਿਤ ਕੀਤਾ। ਐਮਰਜੈਂਸੀ ਸੇਵਾਵਾਂ ਲਈ ਕਿਰਪਾ ਕਰਕੇ 112 ਤੇ ਕਾਲ ਕਰੋ।',
      'sos_active_title_big': 'ਸਰਗਰਮ SOS',
      'sos_active_help_coming': 'ਮਦਦ ਆ ਰਹੀ ਹੈ। ਸ਼ਾਂਤ ਰਹੋ।',
      'sos_active_badge_waiting': 'ਉਡੀਕ',
      'sos_active_badge_en_route_count': '{n} ਰਸਤੇ ਵਿੱਚ',
      'sos_active_mini_ambulance': 'ਐਂਬੂਲੈਂਸ',
      'sos_active_mini_on_scene': 'ਘਟਨਾਵਾਲੀ ਥਾਂ',
      'sos_active_mini_status': 'ਸਥਿਤੀ',
      'sos_active_volunteers_count_short': '{n} ਵਲੰਟੀਅਰ',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title':
          'ਸਾਰੇ ਹਸਪਤਾਲਾਂ ਨੂੰ ਸੂਚਿਤ ਕੀਤਾ',
      'sos_active_all_hospitals_notified_subtitle':
          'ਸਮੇਂ ਸਿਰ ਕੋਈ ਹਸਪਤਾਲ ਸਵੀਕਾਰ ਨਹੀਂ ਹੋਇਆ। ਡਿਸਪੈਚ ਐਮਰਜੈਂਸੀ ਸੇਵਾਵਾਂ ਤੱਕ ਵਧਾ ਰਿਹਾ ਹੈ।',
      'sos_active_position_refresh_note':
          'ਬੈਟਰੀ ਬਚਾਉਣ ਲਈ SOS ਦੌਰਾਨ ਤੁਹਾਡਾ ਸਥਾਨ ਲਗਭਗ ਹਰ 45 ਸਕਿੰਟ ਵਿੱਚ ਰਿਫ੍ਰੈਸ਼ ਹੁੰਦਾ ਹੈ। ਐਪ ਖੋਲ੍ਹੀ ਰੱਖੋ ਅਤੇ ਹੋ ਸਕੇ ਤਾਂ ਚਾਰਜਰ ਲਾਓ।',
      'sos_active_mic_active': 'ਮਾਈਕ · ਸਰਗਰਮ',
      'sos_active_mic_active_detail':
          'ਲਾਈਵ ਚੈਨਲ ਤੁਹਾਡਾ ਮਾਈਕ੍ਰੋਫ਼ੋਨ ਪ੍ਰਾਪਤ ਕਰ ਰਿਹਾ ਹੈ।',
      'sos_active_mic_standby': 'ਮਾਈਕ · ਸਟੈਂਡਬਾਈ',
      'sos_active_mic_standby_detail': 'ਆਵਾਜ਼ ਚੈਨਲ ਲਈ ਉਡੀਕ…',
      'sos_active_mic_connecting': 'ਮਾਈਕ · ਕਨੈਕਟ ਹੋ ਰਿਹਾ',
      'sos_active_mic_connecting_detail':
          'ਐਮਰਜੈਂਸੀ ਆਵਾਜ਼ ਚੈਨਲ ਵਿੱਚ ਸ਼ਾਮਲ ਹੋ ਰਿਹਾ ਹੈ…',
      'sos_active_mic_reconnecting': 'ਮਾਈਕ · ਦੁਬਾਰਾ ਕਨੈਕਟ',
      'sos_active_mic_reconnecting_detail':
          'ਲਾਈਵ ਆਡੀਓ ਮੁੜ ਸਥਾਪਿਤ ਕੀਤਾ ਜਾ ਰਿਹਾ ਹੈ…',
      'sos_active_mic_failed': 'ਮਾਈਕ · ਰੁਕਾਵਟ',
      'sos_active_mic_failed_detail':
          'ਆਵਾਜ਼ ਚੈਨਲ ਉਪਲਬਧ ਨਹੀਂ। ਉੱਪਰ RETRY ਵਰਤੋ।',
      'sos_active_mic_ptt_only': 'ਮਾਈਕ · ਘਟਨਾ ਚੈਨਲ',
      'sos_active_mic_ptt_only_detail':
          'ਓਪਰੇਸ਼ਨਜ਼ ਕਨਸੋਲ ਨੇ Firebase PTT ਰਾਹੀਂ ਆਵਾਜ਼ ਰੂਟ ਕੀਤੀ। ਜਵਾਬਦਾਤਾਵਾਂ ਤੱਕ ਪਹੁੰਚਣ ਲਈ ਬ੍ਰਾਡਕਾਸਟ ਨੂੰ ਦੱਬ ਕੇ ਰੱਖੋ।',
      'sos_active_mic_interrupted': 'ਮਾਈਕ · ਰੁਕਾਵਟ',
      'sos_active_mic_interrupted_detail':
          'ਐਪ ਆਡੀਓ ਪ੍ਰੋਸੈਸ ਕਰਨ ਸਮੇਂ ਛੋਟਾ ਵਿਰਾਮ।',
      'sos_active_consciousness_note':
          'ਸੂਝ ਜਾਂਚਾਂ ਦਾ ਜਵਾਬ ਹਾਂ ਜਾਂ ਨਾਂਹ ਵਿੱਚ ਦਿਓ; ਹੋਰ ਪ੍ਰੋਂਪਟ ਸਕ੍ਰੀਨ ਵਿਕਲਪਾਂ ਦੀ ਵਰਤੋਂ ਕਰਦੇ ਹਨ।',
      'sos_active_live_updates_header': 'ਲਾਈਵ ਅਪਡੇਟਸ',
      'sos_active_live_updates_subtitle':
          'ਡਿਸਪੈਚ, ਵਲੰਟੀਅਰ ਅਤੇ ਡਿਵਾਈਸ',
      'sos_active_live_tag': 'ਲਾਈਵ',
      'sos_active_activity_log': 'ਗਤੀਵਿਧੀ ਲੌਗ',
      'sos_active_header_stat_coordinating_crew': 'ਟੀਮ ਤਾਲਮੇਲ',
      'sos_active_header_stat_coordinating': 'ਤਾਲਮੇਲ',
      'sos_active_header_stat_en_route': 'ਰਾਹ ਵਿੱਚ',
      'sos_active_header_stat_route_min': '~{n} ਮਿੰਟ',
      'sos_active_live_sos_is_live_title': 'SOS ਲਾਈਵ ਹੈ',
      'sos_active_live_sos_is_live_detail':
          'ਤੁਹਾਡਾ ਸਥਾਨ ਅਤੇ ਮੈਡੀਕਲ ਫਲੈਗ ਐਮਰਜੈਂਸੀ ਨੈੱਟਵਰਕ ਉੱਤੇ ਹਨ।',
      'sos_active_live_volunteers_notified_title':
          'ਵਲੰਟੀਅਰਾਂ ਨੂੰ ਸੂਚਿਤ',
      'sos_active_live_volunteers_notified_detail':
          'ਨੇੜਲੇ ਵਲੰਟੀਅਰ ਇਸ ਘਟਨਾ ਨੂੰ ਰੀਅਲ ਟਾਈਮ ਵਿੱਚ ਪ੍ਰਾਪਤ ਕਰਦੇ ਹਨ।',
      'sos_active_live_bridge_connected_title':
          'ਐਮਰਜੈਂਸੀ ਆਵਾਜ਼ ਬ੍ਰਿਜ ਜੁੜਿਆ',
      'sos_active_live_bridge_connected_detail':
          'ਡਿਸਪੈਚ ਡੈਸਕ ਅਤੇ ਜਵਾਬਦਾਤਾ ਇਹ ਚੈਨਲ ਸੁਣ ਸਕਦੇ ਹਨ।',
      'sos_active_live_ptt_title': 'Firebase PTT ਰਾਹੀਂ ਆਵਾਜ਼',
      'sos_active_live_ptt_detail':
          'ਇਸ ਫਲੀਟ ਲਈ ਲਾਈਵ WebRTC ਬ੍ਰਿਜ ਬੰਦ ਹੈ। ਆਵਾਜ਼ ਅਤੇ ਲਿਖਤ ਅਪਡੇਟਾਂ ਲਈ ਬ੍ਰਾਡਕਾਸਟ ਵਰਤੋ।',
      'sos_active_live_contacts_notified_title':
          'ਐਮਰਜੈਂਸੀ ਸੰਪਰਕਾਂ ਨੂੰ ਸੂਚਿਤ',
      'sos_active_live_hospital_accepted_title': 'ਹਸਪਤਾਲ ਨੇ ਸਵੀਕਾਰ ਕੀਤਾ',
      'sos_active_live_ambulance_unit_assigned_title':
          'ਐਂਬੂਲੈਂਸ ਯੂਨਿਟ ਨਿਯੁਕਤ',
      'sos_active_live_ambulance_unit_assigned_subtitle': 'ਯੂਨਿਟ {unit}',
      'sos_active_live_ambulance_en_route_title': 'ਐਂਬੂਲੈਂਸ ਰਸਤੇ ਵਿੱਚ',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'ਰਸਤੇ ਵਿੱਚ',
      'sos_active_live_ambulance_en_route_route_eta': '~{n} ਮਿੰਟ (ਰੂਟ)',
      'sos_active_live_ambulance_coordination_title': 'ਐਂਬੂਲੈਂਸ ਤਾਲਮੇਲ',
      'sos_active_live_ambulance_coordination_pending':
          'ਹਸਪਤਾਲ ਨੇ ਸਵੀਕਾਰ ਕੀਤਾ — ਐਂਬੂਲੈਂਸ ਆਪਰੇਟਰਾਂ ਨੂੰ ਸੂਚਿਤ ਕੀਤਾ ਜਾ ਰਿਹਾ ਹੈ।',
      'sos_active_live_ambulance_coordination_arranging':
          'ਐਂਬੂਲੈਂਸ ਕਰੂ ਦੀ ਵਿਵਸਥਾ — ਯੂਨਿਟ ਰਸਤੇ ਵਿੱਚ ਹੋਣ ਤੇ ਮਿੰਟ ETA।',
      'sos_active_live_responder_status_title': 'ਜਵਾਬਦਾਤਾ ਸਥਿਤੀ',
      'sos_active_live_volunteer_accepted_single_title':
          'ਵਲੰਟੀਅਰ ਸਵੀਕਾਰ',
      'sos_active_live_volunteer_accepted_many_title':
          'ਵਲੰਟੀਅਰਾਂ ਨੇ ਸਵੀਕਾਰ ਕੀਤਾ',
      'sos_active_live_volunteer_accepted_single_detail':
          'ਇੱਕ ਜਵਾਬਦਾਤਾ ਨਿਯੁਕਤ ਹੈ ਅਤੇ ਤੁਹਾਡੇ ਵੱਲ ਆ ਰਿਹਾ ਹੈ।',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} ਜਵਾਬਦਾਤਾ ਇਸ SOS ਲਈ ਨਿਯੁਕਤ ਹਨ।',
      'sos_active_live_volunteer_on_scene_single_title':
          'ਵਲੰਟੀਅਰ ਥਾਂ ਤੇ ਪਹੁੰਚ ਗਿਆ',
      'sos_active_live_volunteer_on_scene_many_title':
          'ਵਲੰਟੀਅਰ ਥਾਂ ਤੇ',
      'sos_active_live_volunteer_on_scene_single_detail':
          'ਕੋਈ ਤੁਹਾਡੇ ਨਾਲ ਜਾਂ ਤੁਹਾਡੇ ਪਿੰਨ ਤੇ ਹੈ।',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} ਜਵਾਬਦਾਤਾ ਥਾਂ ਤੇ ਚਿੰਨ੍ਹਿਤ।',
      'sos_active_live_responder_location_title': 'ਲਾਈਵ ਜਵਾਬਦਾਤਾ ਸਥਾਨ',
      'sos_active_live_responder_location_detail':
          'ਨਿਯੁਕਤ ਵਲੰਟੀਅਰ ਦਾ GPS ਨਕਸ਼ੇ ਤੇ ਅੱਪਡੇਟ ਹੋ ਰਿਹਾ ਹੈ।',
      'sos_active_live_professional_dispatch_title':
          'ਪ੍ਰੋਫੈਸ਼ਨਲ ਡਿਸਪੈਚ ਸਰਗਰਮ',
      'sos_active_live_professional_dispatch_detail':
          'ਤਾਲਮੇਲਿਤ ਸੇਵਾਵਾਂ ਇਸ ਘਟਨਾ ਉੱਤੇ ਕੰਮ ਕਰ ਰਹੀਆਂ ਹਨ।',
      'sos_active_ambulance_200m_detail':
          'ਐਂਬੂਲੈਂਸ ਥਾਂ ਤੇ — ਲਗਭਗ 200 ਮੀਟਰ ਦੇ ਅੰਦਰ।',
      'sos_active_ambulance_200m_semantic_label':
          'ਐਂਬੂਲੈਂਸ ਲਗਭਗ ਦੋ ਸੌ ਮੀਟਰ ਦੇ ਅੰਦਰ ਥਾਂ ਤੇ',
      'sos_active_bridge_channel_on_suffix': ' · {n} ਚੈਨਲ ਉੱਤੇ',
      'sos_active_bridge_channel_voice': 'ਐਮਰਜੈਂਸੀ ਆਵਾਜ਼ ਚੈਨਲ',
      'sos_active_bridge_channel_ptt': 'ਐਮਰਜੈਂਸੀ ਚੈਨਲ · Firebase PTT',
      'sos_active_bridge_channel_failed':
          'ਐਮਰਜੈਂਸੀ ਚੈਨਲ · ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ',
      'sos_active_bridge_channel_connecting':
          'ਐਮਰਜੈਂਸੀ ਚੈਨਲ · ਕਨੈਕਟ ਹੋ ਰਿਹਾ',
      'sos_active_dispatch_contact_hospitals_default':
          'ਤੁਹਾਡੇ ਸਥਾਨ ਅਤੇ ਐਮਰਜੈਂਸੀ ਕਿਸਮ ਦੇ ਆਧਾਰ ਤੇ ਅਸੀਂ ਨੇੜਲੇ ਹਸਪਤਾਲਾਂ ਨਾਲ ਸੰਪਰਕ ਕਰ ਰਹੇ ਹਾਂ।',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'ਐਂਬੂਲੈਂਸ ਕਰੂ ਨੂੰ ਸੂਚਿਤ',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'ਸਾਥੀ ਹਸਪਤਾਲ ਨੇ ਤੁਹਾਡਾ ਕੇਸ ਸਵੀਕਾਰ ਕੀਤਾ। ਐਂਬੂਲੈਂਸ ਆਪਰੇਟਰਾਂ ਨੂੰ ਸੂਚਿਤ ਕੀਤਾ ਜਾ ਰਿਹਾ ਹੈ।',
      'sos_active_dispatch_ambulance_confirmed_title':
          'ਐਂਬੂਲੈਂਸ ਪੁਸ਼ਟੀ',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'ਯੂਨਿਟ {unit} ਤੁਹਾਡੇ ਵੱਲ ਆ ਰਿਹਾ ਹੈ। ਜਿੱਥੇ ਜਵਾਬਦਾਤਾ ਪਹੁੰਚ ਸਕਣ ਉੱਥੇ ਰਹੋ।',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'ਇੱਕ ਐਂਬੂਲੈਂਸ ਤੁਹਾਡੇ ਵੱਲ ਆ ਰਹੀ ਹੈ। ਜਿੱਥੇ ਜਵਾਬਦਾਤਾ ਪਹੁੰਚ ਸਕਣ ਉੱਥੇ ਰਹੋ।',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'ਐਂਬੂਲੈਂਸ ਹੈਂਡਓਫ ਵਿੱਚ ਦੇਰੀ',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'ਹਸਪਤਾਲ ਨੇ ਸਵੀਕਾਰ ਕੀਤਾ, ਪਰ ਸਮੇਂ ਸਿਰ ਕੋਈ ਐਂਬੂਲੈਂਸ ਕਰੂ ਪੁਸ਼ਟੀ ਨਹੀਂ ਹੋਈ। ਡਿਸਪੈਚ ਵਧਾ ਰਿਹਾ ਹੈ — ਲੋੜ ਹੋਵੇ ਤਾਂ 112 ਤੇ ਕਾਲ ਕਰੋ।',
      'sos_active_dispatch_pending_title_trying': 'ਕੋਸ਼ਿਸ਼: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · ਹਸਪਤਾਲ ਜਵਾਬ ਦੀ ਉਡੀਕ।',
      'sos_active_dispatch_accepted_title':
          '{hospital} ਨੇ ਸਵੀਕਾਰ ਕੀਤਾ',
      'sos_active_dispatch_accepted_subtitle':
          'ਐਂਬੂਲੈਂਸ ਡਿਸਪੈਚ ਦਾ ਤਾਲਮੇਲ ਹੋ ਰਿਹਾ ਹੈ।',
      'sos_active_dispatch_exhausted_title':
          'ਸਾਰੇ ਹਸਪਤਾਲਾਂ ਨੂੰ ਸੂਚਿਤ',
      'sos_active_dispatch_exhausted_subtitle':
          'ਸਮੇਂ ਸਿਰ ਕੋਈ ਹਸਪਤਾਲ ਸਵੀਕਾਰ ਨਹੀਂ ਹੋਇਆ। ਡਿਸਪੈਚ ਐਮਰਜੈਂਸੀ ਸੇਵਾਵਾਂ ਤੱਕ ਵਧਾ ਰਿਹਾ ਹੈ।',
      'sos_active_dispatch_generic_title': 'ਹਸਪਤਾਲ ਡਿਸਪੈਚ',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'ਐਮਰਜੈਂਸੀ ਆਵਾਜ਼ ਚੈਨਲ',
      'volunteer_bridge_join_hint_incident':
          'ਸ਼ਾਮਲ ਹੋਣ ਲਈ ਇਹ ਘਟਨਾ ਵਰਤੀ ਜਾਂਦੀ ਹੈ: ਤੁਹਾਡਾ ਨੰਬਰ ਮੇਲ ਖਾਵੇ ਤਾਂ ਐਮਰਜੈਂਸੀ ਸੰਪਰਕ; ਨਹੀਂ ਤਾਂ ਸਵੀਕਾਰਿਆ ਗਿਆ ਵਲੰਟੀਅਰ।',
      'volunteer_bridge_join_hint_elite':
          'ਤੁਸੀਂ ਸਵੀਕਾਰੇ ਗਏ ਜਵਾਬਦਾਤਾ ਹੋਣ ਤੇ ਸ਼ਾਮਲ ਹੋਣਾ ਤੁਹਾਡੇ ਏਲੀਟ ਵਲੰਟੀਅਰ ਪਹੁੰਚ ਵਰਤਦਾ ਹੈ; ਨਹੀਂ ਤਾਂ ਨੰਬਰ ਮੇਲ ਖਾਵੇ ਤਾਂ ਸੰਪਰਕ।',
      'volunteer_bridge_join_hint_desk':
          'ਤੁਸੀਂ ਆਪਣੀ ਪ੍ਰੋਫਾਈਲ ਉੱਤੇ ਐਮਰਜੈਂਸੀ ਸੇਵਾ ਡੈਸਕ ਵਜੋਂ ਡਿਸਪੈਚ ਵਜੋਂ ਸ਼ਾਮਲ ਹੁੰਦੇ ਹੋ।',
      'volunteer_bridge_join_voice_btn': 'ਆਵਾਜ਼ ਵਿੱਚ ਸ਼ਾਮਲ ਹੋਵੋ',
      'volunteer_bridge_connecting_btn': 'ਕਨੈਕਟ ਹੋ ਰਿਹਾ…',
      'volunteer_bridge_incident_id_hint': 'ਘਟਨਾ ID',
      'volunteer_consignment_live_location_hint':
          'ਤੁਸੀਂ ਕਨਸਾਈਨਮੈਂਟ ਤੇ ਹੋਣ ਸਮੇਂ, ਨਕਸ਼ਾ ਅਤੇ ETA ਸਹੀ ਰੱਖਣ ਲਈ ਤੁਹਾਡਾ ਲਾਈਵ ਸਥਾਨ ਇਸ ਘਟਨਾ ਨਾਲ ਸਾਂਝਾ ਹੁੰਦਾ ਹੈ।',
      'volunteer_consignment_low_power_label': 'ਲੋ ਪਾਵਰ',
      'volunteer_consignment_normal_gps_label': 'ਸਧਾਰਨ GPS',
      'bridge_card_incident_id_missing': 'ਘਟਨਾ ID ਗੁੰਮ ਹੈ।',
      'bridge_card_ptt_only_snackbar':
          'ਓਪਰੇਸ਼ਨ ਕੰਸੋਲ ਨੇ ਪੀੜਤ ਦੀ ਆਵਾਜ਼ Firebase PTT ਰਾਹੀਂ ਭੇਜੀ। WebRTC ਬ੍ਰਿਜ ਜੁੜਨਾ ਨਿਸ਼ਕਿਰਿਆ ਹੈ।',
      'bridge_card_ptt_only_banner':
          'ਕੰਸੋਲ ਨੇ Firebase PTT ਰਾਹੀਂ ਆਵਾਜ਼ ਭੇਜੀ — ਇਸ ਫਲੀਟ ਲਈ LiveKit ਬ੍ਰਿਜ ਜੁੜਨਾ ਨਿਸ਼ਕਿਰਿਆ ਹੈ।',
      'bridge_card_connected_snackbar': 'ਵੌਇਸ ਚੈਨਲ ਨਾਲ ਕਨੈਕਟ ਹੋ ਗਏ।',
      'bridge_card_could_not_join': 'ਜੁੜਿਆ ਨਹੀਂ ਜਾ ਸਕਿਆ: {err}',
      'bridge_card_voice_channel_title': 'ਵੌਇਸ ਚੈਨਲ',
      'bridge_card_calm_disclaimer':
          'ਸ਼ਾਂਤ ਰਹੋ ਅਤੇ ਸਪੱਸ਼ਟ ਬੋਲੋ। ਸਥਿਰ ਸੁਰ ਪੀੜਤ ਅਤੇ ਹੋਰ ਮਦਦਗਾਰਾਂ ਦੀ ਮਦਦ ਕਰਦੀ ਹੈ। ਚੀਕੋ ਨਾ ਅਤੇ ਸ਼ਬਦਾਂ ਨੂੰ ਜਲਦਬਾਜ਼ੀ ਨਾਲ ਨਾ ਬੋਲੋ।',
      'bridge_card_cancel': 'ਰੱਦ',
      'bridge_card_join_voice': 'ਵੌਇਸ ਵਿੱਚ ਸ਼ਾਮਲ ਹੋਵੋ',
      'bridge_card_voice_connected': 'ਵੌਇਸ ਜੁੜਿਆ',
      'bridge_card_in_channel': 'ਚੈਨਲ ਵਿੱਚ {n} ਜਣੇ',
      'bridge_card_transmitting': 'ਪ੍ਰਸਾਰਣ ਹੋ ਰਿਹਾ ਹੈ…',
      'bridge_card_hold_to_talk': 'ਬੋਲਣ ਲਈ ਫੜੀ ਰੱਖੋ',
      'bridge_card_disconnect': 'ਡਿਸਕਨੈਕਟ',
      'vol_ems_banner_en_route': 'ਐਂਬੂਲੈਂਸ ਘਟਨਾ ਸਥਾਨ ਵੱਲ',
      'vol_ems_banner_on_scene': 'ਐਂਬੂਲੈਂਸ ਥਾਂ ਤੇ (~200 ਮੀ)',
      'vol_ems_banner_returning': 'ਐਂਬੂਲੈਂਸ ਹਸਪਤਾਲ ਵਾਪਸ ਜਾ ਰਹੀ ਹੈ',
      'vol_ems_banner_complete': 'ਪ੍ਰਤੀਕਿਰਿਆ ਪੂਰੀ · ਐਂਬੂਲੈਂਸ ਸਟੇਸ਼ਨ ਤੇ',
      'vol_ems_banner_complete_with_cycle':
          'ਪ੍ਰਤੀਕਿਰਿਆ ਪੂਰੀ · ਐਂਬੂਲੈਂਸ ਸਟੇਸ਼ਨ ਤੇ · ਕੁੱਲ ਚੱਕਰ {m}ਮਿੰਟ {s}ਸ',
      'vol_tooltip_lifeline_first_aid':
          'ਲਾਈਫਲਾਈਨ — ਮੁੱਢਲੀ ਸਹਾਇਤਾ ਗਾਈਡ (ਪ੍ਰਤੀਕਿਰਿਆ ਤੇ ਰਹਿੰਦੀ ਹੈ)',
      'vol_tooltip_exit_mission': 'ਮਿਸ਼ਨ ਛੱਡੋ',
      'vol_low_power_tracking_hint':
          'ਲੋ-ਪਾਵਰ ਟ੍ਰੈਕਿੰਗ: ਅਸੀਂ ਤੁਹਾਡੀ ਸਥਿਤੀ ਘੱਟ ਵਾਰ, ਵੱਡੀਆਂ ਹਰਕਤਾਂ ਤੋਂ ਬਾਅਦ ਹੀ ਸਿੰਕ ਕਰਦੇ ਹਾਂ। ਡਿਸਪੈਚ ਤੁਹਾਡਾ ਆਖਰੀ ਬਿੰਦੂ ਦੇਖਦਾ ਹੈ।',
      'vol_marker_you': 'ਤੁਸੀਂ',
      'vol_marker_active_unit': 'ਸਰਗਰਮ ਯੂਨਿਟ',
      'vol_marker_practice_incident': 'ਅਭਿਆਸ ਘਟਨਾ',
      'vol_marker_accident_scene': 'ਹਾਦਸਾ ਥਾਂ',
      'vol_marker_training_pin': 'ਸਿਖਲਾਈ ਪਿੰਨ — ਅਸਲ SOS ਨਹੀਂ',
      'vol_marker_high_severity': 'GITM ਕਾਲਜ - ਉੱਚ ਗੰਭੀਰਤਾ',
      'vol_marker_accepted_hospital': 'ਸਵੀਕਾਰ: {hospital}',
      'vol_marker_trying_hospital': 'ਕੋਸ਼ਿਸ਼: {hospital}',
      'vol_marker_ambulance_on_scene': 'ਐਂਬੂਲੈਂਸ ਥਾਂ ਤੇ!',
      'vol_marker_ambulance_en_route': 'ਐਂਬੂਲੈਂਸ ਰਾਹ ਵਿੱਚ',
      'vol_badge_at_scene_pin': 'ਥਾਂ ਪਿੰਨ ਤੇ',
      'vol_badge_in_5km_zone': '5 ਕਿਮੀ ਖੇਤਰ ਵਿੱਚ',
      'vol_badge_en_route': 'ਰਾਹ ਵਿੱਚ',
    },

    // ── Odia (ଓଡ଼ିଆ) ──────────────────────────────────────────────────────
    'or': {
      'app_name': 'EmergencyOS',
      'profile_title': 'ପ୍ରୋଫାଇଲ ଏବଂ ମେଡିକାଲ ଆଇଡି',
      'language': 'ଭାଷା',
      'save_medical_profile': 'ମେଡିକାଲ ପ୍ରୋଫାଇଲ ସେଭ କରନ୍ତୁ',
      'critical_medical_info': 'ଗୁରୁତ୍ୱପୂର୍ଣ୍ଣ ଚିକିତ୍ସା ତଥ୍ୟ',
      'emergency_contacts': 'ଜରୁରୀ ଯୋଗାଯୋଗ',
      'golden_hour_details': 'ଗୋଲ୍ଡେନ ଆୱାର ବିବରଣୀ',
      'sos_lock': 'SOS ଲକ',
      'top_life_savers': 'ସର୍ବୋଚ୍ଚ ଜୀବନ ରକ୍ଷାକାରୀ',
      'lives_saved': 'ବଞ୍ଚାଯାଇଥିବା ଜୀବନ',
      'active_alerts': 'ସକ୍ରିୟ ଆଲର୍ଟ',
      'rank': 'ର୍ୟାଙ୍କ',
      'on_duty': 'ଡ୍ୟୁଟିରେ',
      'standby': 'ଷ୍ଟାଣ୍ଡବାଇ',
      'sos': 'SOS',
      'call_now': 'ଏବେ କଲ କରନ୍ତୁ',
      'quick_guide': 'ଦ୍ରୁତ ଗାଇଡ',
      'detailed_instructions': 'ବିସ୍ତୃତ ନିର୍ଦ୍ଦେଶ',
      'red_flags': 'ବିପଦ ସଙ୍କେତ',
      'cautions': 'ସତର୍କତା',
      'voice_walkthrough': 'ଭଏସ ଗାଇଡ',
      'playing': 'ଚାଲୁଛି...',
      'swipe_next_guide': 'ପରବର୍ତ୍ତୀ ଗାଇଡ ପାଇଁ ସ୍ୱାଇପ କରନ୍ତୁ',
      'watch_video_guide': 'ସମ୍ପୂର୍ଣ୍ଣ ଭିଡିଓ ଗାଇଡ ଦେଖନ୍ତୁ',
      'emergency_grid_scan': 'ଜରୁରୀ ଗ୍ରିଡ ସ୍କାନ',
      'area_telemetry': 'ଅଞ୍ଚଳ ଟେଲିମେଟ୍ରି ଏବଂ ବିପଦ ସୂଚକ',
      'report_hazard': 'ବିପଦ ରିପୋର୍ଟ କରନ୍ତୁ',
      'todays_duty': 'ଆଜିର ଡ୍ୟୁଟି',
      'blood_type': 'ରକ୍ତ ଗ୍ରୁପ',
      'allergies': 'ଆଲର୍ଜି',
      'medical_conditions': 'ଚିକିତ୍ସା ଅବସ୍ଥା',
      'contact_name': 'ପ୍ରାଥମିକ ଯୋଗାଯୋଗ ନାମ',
      'contact_phone': 'ପ୍ରାଥମିକ ଯୋଗାଯୋଗ ଫୋନ',
      'relationship': 'ସମ୍ପର୍କ',
      'medications': 'ବର୍ତ୍ତମାନ ଔଷଧ',
      'organ_donor': 'ଅଙ୍ଗ ଦାନ ସ୍ଥିତି',
      'good_morning': 'ସୁପ୍ରଭାତ,',
      'good_afternoon': 'ଶୁଭ ଅପରାହ୍ନ,',
      'good_evening': 'ଶୁଭ ସନ୍ଧ୍ୟା,',
      'hospitals': 'ଡାକ୍ତରଖାନା',
      'visual_walkthrough': 'ଭିଜୁଆଲ ଗାଇଡ',
      'lifeline': 'ଲାଇଫଲାଇନ',
      'nav_home': 'ହୋମ',
      'nav_map': 'ମ୍ୟାପ',
      'nav_grid': 'ଗ୍ରିଡ୍',
      'nav_profile': 'ପ୍ରୋଫାଇଲ',
      'map_caching_offline_pct': 'ଅଫଲାଇନ୍ ପାଇଁ କ୍ଷେତ୍ର କ୍ୟାସ୍ ହେଉଛି — {pct}%',
      'map_drill_practice_banner':
          'ଅଭ୍ୟାସ ଗ୍ରିଡ୍: ପଲ୍ସିଂ ପିନ୍ = ଡେମୋ ସକ୍ରିୟ ସତର୍କତା। ସ୍ତର ପାଇଁ ମାନଚିତ୍ର ଫିଲ୍ଟର — ପ୍ରକୃତ ଡାଟା ନୁହେଁ।',
      'map_recenter_tooltip': 'ପୁନର୍କେନ୍ଦ୍ରିତ କରନ୍ତୁ',
      'map_legend_hospital': 'ଡାକ୍ତରଖାନା',
      'map_legend_live_sos_history': 'ଲାଇଭ୍ SOS / ଇତିହାସ',
      'map_legend_past_this_hex': 'ଅତୀତ (ଏହି ହେକ୍ସ)',
      'map_legend_in_area': 'କ୍ଷେତ୍ରରେ {n}',
      'map_legend_in_cell': 'ସେଲରେ {n}',
      'map_legend_volunteers_on_duty': 'ଡ୍ୟୁଟିରେ ସ୍ୱେଚ୍ଛାସେବୀ',
      'map_legend_volunteers_in_grid': 'ଗ୍ରିଡରେ {n}',
      'map_legend_responder_scene': 'ପ୍ରତିକ୍ରିୟାକାରୀ → ଦୃଶ୍ୟ',
      'map_responder_routes_one': '{n} ମାର୍ଗ',
      'map_responder_routes_many': '{n} ମାର୍ଗ',
      'map_filters_title': 'ମାନଚିତ୍ର ଫିଲ୍ଟର',
      'step_prefix': 'ପଦକ୍ଷେପ',
      'highlights_steps': 'ଗୋଟିଏ ଗୋଟିଏ କରି ପଦକ୍ଷେପ ଦେଖାଏ',
      'offline_mode': 'ଅଫଲାଇନ — ନେଟୱାର୍କ ବିଚ୍ଛିନ୍ନ',
      'volunteer': 'ସ୍ୱେଚ୍ଛାସେବୀ',
      'unranked': 'ର୍ୟାଙ୍କ ନାହିଁ',
      'live': 'ଲାଇଭ',
      'you': 'ଆପଣ',
      'saved': 'ବଞ୍ଚାଇଲେ',
      'xp_responses': 'XP · {0} ପ୍ରତିକ୍ରିୟା',
      'duty_monitoring': 'ଆପଣ ଡ୍ୟୁଟିରେ ଥିବାବେଳେ SOS ପପ-ଅପ ଚାଲୁ ଅଛି।',
      'turn_on_duty_msg': 'SOS ପପ-ଅପ ପାଇବା ପାଇଁ ଡ୍ୟୁଟି ଚାଲୁ କରନ୍ତୁ।',
      'on_duty_snack': 'ଡ୍ୟୁଟିରେ — ଆପଣଙ୍କ ଅଞ୍ଚଳରେ ଘଟଣା ନଜର ରଖୁଛି...',
      'off_duty_snack': 'ଷ୍ଟାଣ୍ଡବାଇ — ଡ୍ୟୁଟି ସେସନ ରେକର୍ଡ ହେଲା।',
      'leaderboard_offline': 'ଲୀଡରବୋର୍ଡ ଅଫଲାଇନ',
      'leaderboard_offline_sub': 'ସିଙ୍କ ବନ୍ଦ। କ୍ୟାସ ସ୍କୋର।',
      'set_sos_pin_first': 'ପ୍ରଥମେ SOS ପିନ ସେଟ କରନ୍ତୁ',
      'set_pin_safety_msg': 'ସୁରକ୍ଷା ପାଇଁ, SOS ସୃଷ୍ଟି କରିବା ପୂର୍ବରୁ ପିନ ସେଟ କରିବା ଆବଶ୍ୟକ।',
      'set_pin_now': 'ଏବେ ପିନ ସେଟ କରନ୍ତୁ',
      'later': 'ପରେ',
      'sos_are_you_conscious':
          'ଆପଣ ସଚେତ ଅଛନ୍ତି କି? ଦୟାକରି ହଁ କିମ୍ବା ନା ଉତ୍ତର ଦିଅନ୍ତୁ।',
      'sos_tts_opening_guidance':
          'ଆପଣଙ୍କ SOS ସକ୍ରିୟ। ସାହାଯ୍ୟ ଆସୁଛି। କୁହାଯାଇଥିବା ନିର୍ଦ୍ଦେଶ ଅନୁସରଣ କରନ୍ତୁ ଏବଂ ଉତ୍ତର ଦେବାକୁ ଟ୍ୟାପ୍ କରନ୍ତୁ।',
      'sos_interview_q1_prompt': 'କଣ ହେଉଛି? (ଜରୁରୀ ପ୍ରକାର)',
      'sos_interview_q2_prompt': 'ଆପଣ ସୁରକ୍ଷିତ କି? କେତେ ଗୁରୁତର?',
      'sos_interview_q3_prompt': 'କେତେ ଜଣ ଜଡିତ?',
      'sos_chip_cat_accident': 'ଦୁର୍ଘଟଣା',
      'sos_chip_cat_medical': 'ଚିକିତ୍ସା',
      'sos_chip_cat_hazard': 'ବିପଦ (ଅଗ୍ନି, ବୁଡିବା ଇତ୍ୟାଦି)',
      'sos_chip_cat_assault': 'ଆକ୍ରମଣ',
      'sos_chip_cat_other': 'ଅନ୍ୟ',
      'sos_chip_safe_critical': 'ଗୁରୁତର (ଜୀବନ ବିପଦ)',
      'sos_chip_safe_injured': 'ଆଘାତ କିନ୍ତୁ ସ୍ଥିର',
      'sos_chip_safe_danger': 'ଆଘାତ ନାହିଁ କିନ୍ତୁ ବିପଦରେ',
      'sos_chip_safe_safe_now': 'ଏବେ ସୁରକ୍ଷିତ',
      'sos_chip_people_me': 'କେବଳ ମୁଁ',
      'sos_chip_people_two': 'ଦୁଇଜଣ',
      'sos_chip_people_many': 'ଦୁଇଠାରୁ ଅଧିକ',
      'sos_tts_interview_saved':
          'ସମସ୍ତ ସାକ୍ଷାତକାର ଡାଟା ସେଭ୍ ହେଲା। ପ୍ରତିକ୍ରିୟାକାରୀଙ୍କ ପାଖରେ ବିବରଣୀ ଅଛି।',
      'sos_tts_map_routes':
          'ମ୍ୟାପ୍ ଟ୍ୟାବ୍ ଖୋଲନ୍ତୁ: ଲାଲ୍ ନିୟୁକ୍ତ ଡାକ୍ତରଖାନାକୁ ରାସ୍ତା କିମ୍ବା ନିକଟ ମାର୍ଗ; ସବୁଜ ସ୍ୱେଚ୍ଛାସେବୀ ମାର୍ଗ। ଜରୁରୀ ଭଏସ୍ ଚ୍ୟାନେଲରେ ରୁହନ୍ତୁ।',
      'sos_tts_emergency_contacts_on_file':
          'Your emergency contact from your profile is attached to this SOS. SMS updates may be sent when that option is enabled.',
      'sos_tts_conscious_no_answer_attempt':
          'ଉତ୍ତର ନାହିଁ। ସଚେତନତା ଯାଞ୍ଚ {max} ରେ {n}। ଏକ ମିନିଟ୍ ପରେ ପୁନଃ ପଚାରିବୁ।',
      'voice_volunteer_accepted':
          'ସ୍ୱେଚ୍ଛାସେବୀ ଗ୍ରହଣ କଲେ। ସାହାଯ୍ୟ ଆସୁଛି।',
      'voice_ambulance_dispatched_eta':
          'ଆମ୍ବୁଲାନ୍ସ ପଠାଗଲା। ଅନୁମାନିତ ଆଗମନ: {eta}।',
      'voice_police_dispatched_eta':
          'ପୋଲିସ ପଠାଗଲା। ଅନୁମାନିତ ଆଗମନ: {eta}।',
      'voice_ambulance_on_scene_victim':
          'ଆମ୍ବୁଲାନ୍ସ ଘଟଣାସ୍ଥଳରେ — ଆପଣଙ୍କଠାରୁ ପ୍ରାୟ ଦୁଇଶହ ମିଟର ଦୂରରେ।',
      'voice_ambulance_on_scene_volunteer':
          'ଆମ୍ବୁଲାନ୍ସ ଘଟଣାସ୍ଥଳରେ — ଘଟଣାସ୍ଥଳଠାରୁ ପ୍ରାୟ ଦୁଇଶହ ମିଟର ଭିତରେ।',
      'voice_ambulance_returning': 'ଆମ୍ବୁଲାନ୍ସ ଡାକ୍ତରଖାନାକୁ ଫେରୁଛି।',
      'voice_response_complete_station':
          'ପ୍ରତିକ୍ରିୟା ସମ୍ପୂର୍ଣ୍ଣ। ଆମ୍ବୁଲାନ୍ସ ଷ୍ଟେସନରେ।',
      'voice_response_complete_cycle':
          'ପ୍ରତିକ୍ରିୟା ସମ୍ପୂର୍ଣ୍ଣ। ଆମ୍ବୁଲାନ୍ସ ଷ୍ଟେସନରେ। ମୋଟ ଚକ୍ର {minutes} ମିନିଟ୍ {seconds} ସେକେଣ୍ଡ।',
      'voice_volunteers_on_scene_count':
          '{n} ଜଣ ସ୍ୱେଚ୍ଛାସେବୀ ଏବେ ଘଟଣାସ୍ଥଳରେ।',
      'voice_one_volunteer_on_scene': 'ଜଣେ ସ୍ୱେଚ୍ଛାସେବୀ ଘଟଣାସ୍ଥଳରେ।',
      'voice_ptt_joined_comms': '{who} ଭଏସ୍ ଯୋଗାଯୋଗରେ ଯୋଗ ଦେଲେ।',
      'voice_tts_unavailable_banner':
          'ଭଏସ୍ ମାର୍ଗଦର୍ଶନ ଉପଲବ୍ଧ ନୁହେଁ — ସ୍କ୍ରିନ୍ ଲେଖା ପଢ଼ନ୍ତୁ।',
      'language_picker_title': 'ଭାଷା',
      'volunteer_victim_medical_card': 'ପୀଡିତ ମେଡିକାଲ୍ କାର୍ଡ',
      'volunteer_dispatch_milestone_title': 'ଡିସପାଚ୍ ଅପଡେଟ୍',
      'volunteer_dispatch_milestone_hospital': 'ଡାକ୍ତରଖାନା ଗ୍ରହଣ କଲା: {hospital}',
      'volunteer_dispatch_milestone_unit': 'ଆମ୍ବୁଲାନ୍ସ ୟୁନିଟ୍: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'ଆମ୍ବୁଲାନ୍ସ କ୍ରୁ: ସମନ୍ୱୟ…',
      'volunteer_dispatch_milestone_en_route': 'ଆମ୍ବୁଲାନ୍ସ ମାର୍ଗରେ',
      'volunteer_triage_qr_report_title': 'QR କିମ୍ବା ଟ୍ୟାପ୍ ରିପୋର୍ଟ',
      'volunteer_triage_qr_report_subtitle':
          'ହ୍ୟାଣ୍ଡଅଫ୍ ପାଇଁ କୋଡ୍ ସ୍କାନ୍ କରନ୍ତୁ କିମ୍ବା ଘଟଣା ରିପୋର୍ଟ ସେଭ୍ ପାଇଁ ଟ୍ୟାପ୍ କରନ୍ତୁ।',
      'volunteer_triage_show_qr': 'QR ଦେଖାନ୍ତୁ',
      'volunteer_triage_tap_report': 'ରିପୋର୍ଟ',
      'volunteer_triage_qr_title': 'ଘଟଣା ହ୍ୟାଣ୍ଡଅଫ୍ QR',
      'volunteer_triage_qr_body': 'ଗଠନାତ୍ମକ ଡାଟା ପାଇଁ ଷ୍ଟାଫ୍ କିମ୍ବା EMS ସହ ସେୟାର୍ କରନ୍ତୁ।',
      'volunteer_triage_report_saved': 'ରିପୋର୍ଟ ଏହି ଘଟଣା ତଳେ ସେଭ୍ ହେଲା।',
      'volunteer_triage_report_failed': 'ରିପୋର୍ଟ ସେଭ୍ ହେଲା ନାହିଁ: ',
      'volunteer_victim_medical_offline_hint': 'SOS ପ୍ୟାକେଟ୍ ଠାରୁ — ଅଫଲାଇନ୍ କ୍ୟାଶରୁ।',
      'volunteer_victim_consciousness_title': 'ସଚେତନତା',
      'volunteer_victim_three_questions': 'ଆରମ୍ଭିକ ଉତ୍ତର',
      'volunteer_major_updates_log': 'କେବଳ ମୁଖ୍ୟ ଅପଡେଟ୍',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'ଟିଅର {tier} ପର୍ଯ୍ୟନ୍ତ ବୃଦ୍ଧି କରୁଛୁ। ଡାକ୍ତରଖାନା {hospital} ଚେଷ୍ଟା କରୁଛୁ।',
      'volunteer_dispatch_trying_hospital': 'ଡାକ୍ତରଖାନା {hospital} ଚେଷ୍ଟା କରୁଛୁ।',
      'volunteer_dispatch_hospital_accepted':
          '{hospital} ଜରୁରୀ ଗ୍ରହଣ କଲା। ଆମ୍ବୁଲାନ୍ସ ସମନ୍ୱୟ ଚାଲିଛି।',
      'volunteer_dispatch_all_hospitals_notified':
          'ସମସ୍ତ ଡାକ୍ତରଖାନାକୁ ସୂଚିତ କଲୁ। ଜରୁରୀ ସେବାକୁ ବଢ଼ାଉଛୁ।',
      'sos_dispatch_alerting_nearest_trying':
          'ଆପଣଙ୍କ ଅଞ୍ଚଳର ନିକଟତମ ଡାକ୍ତରଖାନାକୁ ସତର୍କ କରୁଛୁ। {hospital} ଚେଷ୍ଟା କରୁଛୁ।',
      'sos_dispatch_escalating_tier_trying':
          'କୌଣସି ଉତ୍ତର ନାହିଁ। ଟିଅର {tier} ପର୍ଯ୍ୟନ୍ତ ବୃଦ୍ଧି କରୁଛୁ। {hospital} ଚେଷ୍ଟା କରୁଛୁ।',
      'sos_dispatch_retry_previous_trying':
          'ପୂର୍ବ ଡାକ୍ତରଖାନାରୁ ଉତ୍ତର ନାହିଁ। {hospital} ଚେଷ୍ଟା କରୁଛୁ।',
      'sos_dispatch_all_hospitals_call_112':
          'ସମସ୍ତ ଡାକ୍ତରଖାନାକୁ ସୂଚିତ କଲୁ। ଜରୁରୀ ସେବା ପାଇଁ ଦୟାକରି 112 କୁ କଲ୍ କରନ୍ତୁ।',
      'sos_active_title_big': 'ସକ୍ରିୟ SOS',
      'sos_active_help_coming': 'ସାହାଯ୍ୟ ଆସୁଛି। ଶାନ୍ତ ରୁହନ୍ତୁ।',
      'sos_active_badge_waiting': 'ଅପେକ୍ଷା',
      'sos_active_badge_en_route_count': '{n} ରାସ୍ତାରେ',
      'sos_active_mini_ambulance': 'ଆମ୍ବୁଲାନ୍ସ',
      'sos_active_mini_on_scene': 'ସ୍ଥାନରେ',
      'sos_active_mini_status': 'ସ୍ଥିତି',
      'sos_active_volunteers_count_short': '{n} ସ୍ୱେଚ୍ଛାସେବକ',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title':
          'ସମସ୍ତ ଡାକ୍ତରଖାନାକୁ ସୂଚିତ କଲୁ',
      'sos_active_all_hospitals_notified_subtitle':
          'ସମୟରେ କୌଣସି ଡାକ୍ତରଖାନା ଗ୍ରହଣ କଲା ନାହିଁ। ଡିସ୍ପାଚ୍ ଜରୁରୀ ସେବାକୁ ବଢ଼ାଉଛି।',
      'sos_active_position_refresh_note':
          'ବ୍ୟାଟେରୀ ସଞ୍ଚୟ କରିବା ପାଇଁ SOS ସମୟରେ ଆପଣଙ୍କ ସ୍ଥାନ ପ୍ରାୟ ପ୍ରତି 45 ସେକେଣ୍ଡରେ ତାଜା ହୁଏ। ଆପ୍ ଖୋଲା ରଖନ୍ତୁ ଏବଂ ସମ୍ଭବ ହେଲେ ଚାର୍ଜରେ ଲଗାନ୍ତୁ।',
      'sos_active_mic_active': 'ମାଇକ୍ · ସକ୍ରିୟ',
      'sos_active_mic_active_detail':
          'ଲାଇଭ୍ ଚ୍ୟାନେଲ୍ ଆପଣଙ୍କ ମାଇକ୍ରୋଫୋନ୍ ଗ୍ରହଣ କରୁଛି।',
      'sos_active_mic_standby': 'ମାଇକ୍ · ଷ୍ଟାଣ୍ଡବାଇ',
      'sos_active_mic_standby_detail': 'ଭଏସ୍ ଚ୍ୟାନେଲ୍ ଅପେକ୍ଷାରେ…',
      'sos_active_mic_connecting': 'ମାଇକ୍ · ସଂଯୋଗ ହେଉଛି',
      'sos_active_mic_connecting_detail':
          'ଜରୁରୀ ଭଏସ୍ ଚ୍ୟାନେଲରେ ଯୋଗ ହେଉଛି…',
      'sos_active_mic_reconnecting': 'ମାଇକ୍ · ପୁନଃ ସଂଯୋଗ',
      'sos_active_mic_reconnecting_detail':
          'ଲାଇଭ୍ ଅଡିଓକୁ ପୁନରୁଦ୍ଧାର କରୁଛି…',
      'sos_active_mic_failed': 'ମାଇକ୍ · ବାଧା',
      'sos_active_mic_failed_detail':
          'ଭଏସ୍ ଚ୍ୟାନେଲ୍ ଉପଲବ୍ଧ ନାହିଁ। ଉପରେ RETRY ବ୍ୟବହାର କରନ୍ତୁ।',
      'sos_active_mic_ptt_only': 'ମାଇକ୍ · ଘଟଣା ଚ୍ୟାନେଲ',
      'sos_active_mic_ptt_only_detail':
          'ଅପରେସନ୍ସ କନସୋଲ୍ Firebase PTT ଦ୍ୱାରା ଭଏସ୍ ରୁଟ୍ କରିଛି। ଉତ୍ତରଦାତାଙ୍କ ପର୍ଯ୍ୟନ୍ତ ପହଞ୍ଚିବାକୁ ବ୍ରଡକାଷ୍ଟ ଧରନ୍ତୁ।',
      'sos_active_mic_interrupted': 'ମାଇକ୍ · ବାଧିତ',
      'sos_active_mic_interrupted_detail':
          'ଆପ୍ ଅଡିଓ ପ୍ରୋସେସ୍ କରୁଥିବା ସମୟରେ ଛୋଟ ବିରତି।',
      'sos_active_consciousness_note':
          'ଚେତନା ଯାଞ୍ଚର ଉତ୍ତର ହଁ କିମ୍ବା ନା ରେ ଦିଅନ୍ତୁ; ଅନ୍ୟ ପ୍ରଂପ୍ଟ ସ୍କ୍ରିନ୍ ବିକଳ୍ପ ବ୍ୟବହାର କରନ୍ତି।',
      'sos_active_live_updates_header': 'ଲାଇଭ୍ ଅପଡେଟ୍',
      'sos_active_live_updates_subtitle':
          'ଡିସ୍ପାଚ୍, ସ୍ୱେଚ୍ଛାସେବକ ଏବଂ ଡିଭାଇସ୍',
      'sos_active_live_tag': 'ଲାଇଭ୍',
      'sos_active_activity_log': 'କାର୍ଯ୍ୟକଳାପ ଲଗ୍',
      'sos_active_header_stat_coordinating_crew': 'କର୍ମଚାରୀ ସମନ୍ୱୟ',
      'sos_active_header_stat_coordinating': 'ସମନ୍ୱୟ',
      'sos_active_header_stat_en_route': 'ପଥରେ',
      'sos_active_header_stat_route_min': '~{n} ମିନିଟ୍',
      'sos_active_live_sos_is_live_title': 'SOS ଲାଇଭ୍',
      'sos_active_live_sos_is_live_detail':
          'ଆପଣଙ୍କ ସ୍ଥାନ ଓ ଚିକିତ୍ସା ଫ୍ଲାଗ୍ ଜରୁରୀ ନେଟୱାର୍କରେ ଅଛି।',
      'sos_active_live_volunteers_notified_title':
          'ସ୍ୱେଚ୍ଛାସେବକଙ୍କୁ ସୂଚିତ',
      'sos_active_live_volunteers_notified_detail':
          'ନିକଟସ୍ଥ ସ୍ୱେଚ୍ଛାସେବକ ଏହି ଘଟଣାକୁ ରିଆଲ୍ ଟାଇମ୍ ରେ ପାଆନ୍ତି।',
      'sos_active_live_bridge_connected_title':
          'ଜରୁରୀ ଭଏସ୍ ବ୍ରିଜ୍ ସଂଯୋଗ',
      'sos_active_live_bridge_connected_detail':
          'ଡିସ୍ପାଚ୍ ଡେସ୍କ ଓ ଉତ୍ତରଦାତା ଏହି ଚ୍ୟାନେଲ୍ ଶୁଣିପାରିବେ।',
      'sos_active_live_ptt_title': 'Firebase PTT ମାଧ୍ୟମରେ ଭଏସ୍',
      'sos_active_live_ptt_detail':
          'ଏହି ଫ୍ଲିଟ୍ ପାଇଁ ଲାଇଭ୍ WebRTC ବ୍ରିଜ୍ ବନ୍ଦ। ଭଏସ୍ ଓ ଟେକ୍ସ୍ଟ ଅପଡେଟ୍ ପାଇଁ ବ୍ରଡକାଷ୍ଟ ବ୍ୟବହାର କରନ୍ତୁ।',
      'sos_active_live_contacts_notified_title':
          'ଜରୁରୀ ସମ୍ପର୍କକୁ ସୂଚିତ',
      'sos_active_live_hospital_accepted_title': 'ଡାକ୍ତରଖାନା ଗ୍ରହଣ',
      'sos_active_live_ambulance_unit_assigned_title':
          'ଆମ୍ବୁଲାନ୍ସ ଇଉନିଟ୍ ନିଯୁକ୍ତ',
      'sos_active_live_ambulance_unit_assigned_subtitle':
          'ଇଉନିଟ୍ {unit}',
      'sos_active_live_ambulance_en_route_title': 'ଆମ୍ବୁଲାନ୍ସ ରାସ୍ତାରେ',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'ରାସ୍ତାରେ',
      'sos_active_live_ambulance_en_route_route_eta': '~{n} ମିନିଟ୍ (ରୁଟ୍)',
      'sos_active_live_ambulance_coordination_title': 'ଆମ୍ବୁଲାନ୍ସ ସମନ୍ୱୟ',
      'sos_active_live_ambulance_coordination_pending':
          'ଡାକ୍ତରଖାନା ଗ୍ରହଣ କରିଛି — ଆମ୍ବୁଲାନ୍ସ ଅପରେଟରଙ୍କୁ ସୂଚିତ କରାଯାଉଛି।',
      'sos_active_live_ambulance_coordination_arranging':
          'ଆମ୍ବୁଲାନ୍ସ କ୍ରୁ ବ୍ୟବସ୍ଥା — ଇଉନିଟ୍ ରାସ୍ତାରେ ଥିବା ବେଳେ ମିନିଟ୍ ETA।',
      'sos_active_live_responder_status_title': 'ଉତ୍ତରଦାତାର ସ୍ଥିତି',
      'sos_active_live_volunteer_accepted_single_title':
          'ସ୍ୱେଚ୍ଛାସେବକ ଗ୍ରହଣ',
      'sos_active_live_volunteer_accepted_many_title':
          'ସ୍ୱେଚ୍ଛାସେବକମାନେ ଗ୍ରହଣ କଲେ',
      'sos_active_live_volunteer_accepted_single_detail':
          'ଜଣେ ଉତ୍ତରଦାତା ନିଯୁକ୍ତ ଏବଂ ଆପଣଙ୍କ ନିକଟକୁ ଆସୁଛନ୍ତି।',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} ଉତ୍ତରଦାତା ଏହି SOS ପାଇଁ ନିଯୁକ୍ତ।',
      'sos_active_live_volunteer_on_scene_single_title':
          'ସ୍ୱେଚ୍ଛାସେବକ ଘଟଣାସ୍ଥଳରେ ପହଞ୍ଚିଲେ',
      'sos_active_live_volunteer_on_scene_many_title':
          'ସ୍ୱେଚ୍ଛାସେବକମାନେ ଘଟଣାସ୍ଥଳରେ',
      'sos_active_live_volunteer_on_scene_single_detail':
          'କେହି ଆପଣଙ୍କ ସହିତ କିମ୍ବା ଆପଣଙ୍କ ପିନରେ ଅଛନ୍ତି।',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} ଉତ୍ତରଦାତା ଘଟଣାସ୍ଥଳରେ ଚିହ୍ନିତ।',
      'sos_active_live_responder_location_title':
          'ଲାଇଭ୍ ଉତ୍ତରଦାତାର ସ୍ଥାନ',
      'sos_active_live_responder_location_detail':
          'ନିଯୁକ୍ତ ସ୍ୱେଚ୍ଛାସେବକର GPS ମାନଚିତ୍ରରେ ଅପଡେଟ୍ ହେଉଛି।',
      'sos_active_live_professional_dispatch_title':
          'ପେସାଦାର ଡିସ୍ପାଚ୍ ସକ୍ରିୟ',
      'sos_active_live_professional_dispatch_detail':
          'ସମନ୍ୱିତ ସେବାଗୁଡ଼ିକ ଏହି ଘଟଣାରେ କାମ କରୁଛନ୍ତି।',
      'sos_active_ambulance_200m_detail':
          'ଆମ୍ବୁଲାନ୍ସ ଘଟଣାସ୍ଥଳରେ — ପ୍ରାୟ 200 ମିଟର ମଧ୍ୟରେ।',
      'sos_active_ambulance_200m_semantic_label':
          'ଆମ୍ବୁଲାନ୍ସ ପ୍ରାୟ ଦୁଇଶହ ମିଟର ମଧ୍ୟରେ ଘଟଣାସ୍ଥଳରେ',
      'sos_active_bridge_channel_on_suffix': ' · {n} ଚ୍ୟାନେଲରେ',
      'sos_active_bridge_channel_voice': 'ଜରୁରୀ ଭଏସ୍ ଚ୍ୟାନେଲ୍',
      'sos_active_bridge_channel_ptt': 'ଜରୁରୀ ଚ୍ୟାନେଲ୍ · Firebase PTT',
      'sos_active_bridge_channel_failed':
          'ଜରୁରୀ ଚ୍ୟାନେଲ୍ · ପୁନଃ ଚେଷ୍ଟା କରନ୍ତୁ',
      'sos_active_bridge_channel_connecting':
          'ଜରୁରୀ ଚ୍ୟାନେଲ୍ · ସଂଯୋଗ ହେଉଛି',
      'sos_active_dispatch_contact_hospitals_default':
          'ଆପଣଙ୍କ ସ୍ଥାନ ଓ ଜରୁରୀ ପ୍ରକାର ଆଧାରରେ ଆମେ ନିକଟସ୍ଥ ଡାକ୍ତରଖାନାଗୁଡ଼ିକ ସହ ଯୋଗାଯୋଗ କରୁଛୁ।',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'ଆମ୍ବୁଲାନ୍ସ କ୍ରୁକୁ ସୂଚିତ',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'ଭାଗୀଦାର ଡାକ୍ତରଖାନା ଆପଣଙ୍କ କେସ୍ ଗ୍ରହଣ କଲା। ଆମ୍ବୁଲାନ୍ସ ଅପରେଟରଙ୍କୁ ସୂଚିତ କରାଯାଉଛି।',
      'sos_active_dispatch_ambulance_confirmed_title':
          'ଆମ୍ବୁଲାନ୍ସ ନିଶ୍ଚିତ',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'ଇଉନିଟ୍ {unit} ଆପଣଙ୍କ ନିକଟକୁ ଆସୁଛି। ଯେଉଁଠାରେ ଉତ୍ତରଦାତା ପହଞ୍ଚିପାରିବେ ସେଠାରେ ରୁହନ୍ତୁ।',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'ଏକ ଆମ୍ବୁଲାନ୍ସ ଆପଣଙ୍କ ନିକଟକୁ ଆସୁଛି। ଯେଉଁଠାରେ ଉତ୍ତରଦାତା ପହଞ୍ଚିପାରିବେ ସେଠାରେ ରୁହନ୍ତୁ।',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'ଆମ୍ବୁଲାନ୍ସ ହସ୍ତାନ୍ତରରେ ବିଳମ୍ବ',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'ଡାକ୍ତରଖାନା ଗ୍ରହଣ କଲା, କିନ୍ତୁ ସମୟରେ କୌଣସି ଆମ୍ବୁଲାନ୍ସ କ୍ରୁ ନିଶ୍ଚିତ ହେଲା ନାହିଁ। ଡିସ୍ପାଚ୍ ବଢ଼ାଉଛି — ଆବଶ୍ୟକ ହେଲେ 112 କୁ କଲ୍ କରନ୍ତୁ।',
      'sos_active_dispatch_pending_title_trying':
          'ଚେଷ୍ଟା: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · ଡାକ୍ତରଖାନା ଉତ୍ତରର ଅପେକ୍ଷା।',
      'sos_active_dispatch_accepted_title':
          '{hospital} ଗ୍ରହଣ କଲା',
      'sos_active_dispatch_accepted_subtitle':
          'ଆମ୍ବୁଲାନ୍ସ ଡିସ୍ପାଚ୍ ସମନ୍ୱୟ ହେଉଛି।',
      'sos_active_dispatch_exhausted_title':
          'ସମସ୍ତ ଡାକ୍ତରଖାନାକୁ ସୂଚିତ',
      'sos_active_dispatch_exhausted_subtitle':
          'ସମୟରେ କୌଣସି ଡାକ୍ତରଖାନା ଗ୍ରହଣ କଲା ନାହିଁ। ଡିସ୍ପାଚ୍ ଜରୁରୀ ସେବାକୁ ବଢ଼ାଉଛି।',
      'sos_active_dispatch_generic_title': 'ଡାକ୍ତରଖାନା ଡିସ୍ପାଚ୍',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'ଜରୁରୀ ଭଏସ୍ ଚ୍ୟାନେଲ୍',
      'volunteer_bridge_join_hint_incident':
          'ଯୋଗ ଦେବା ପାଇଁ ଏହି ଘଟଣା ବ୍ୟବହୃତ ହୁଏ: ଆପଣଙ୍କ ନମ୍ବର ମିଳିଲେ ଜରୁରୀ ସମ୍ପର୍କ; ନହେଲେ ଗ୍ରହୀତ ସ୍ୱେଚ୍ଛାସେବକ।',
      'volunteer_bridge_join_hint_elite':
          'ଆପଣ ଗ୍ରହୀତ ଉତ୍ତରଦାତା ହୋଇଥିଲେ ଯୋଗଦାନ ଆପଣଙ୍କ ଏଲିଟ୍ ପ୍ରବେଶ ବ୍ୟବହାର କରେ; ନହେଲେ ନମ୍ବର ମିଳିଲେ ସମ୍ପର୍କ।',
      'volunteer_bridge_join_hint_desk':
          'ଆପଣଙ୍କ ପ୍ରୋଫାଇଲରେ ଜରୁରୀ ସେବା ଡେସ୍କ ଭାବେ ଆପଣ ଡିସ୍ପାଚ୍ ଭାବେ ଯୋଗ ଦିଅନ୍ତି।',
      'volunteer_bridge_join_voice_btn': 'ଭଏସରେ ଯୋଗ ଦିଅନ୍ତୁ',
      'volunteer_bridge_connecting_btn': 'ସଂଯୋଗ ହେଉଛି…',
      'volunteer_bridge_incident_id_hint': 'ଘଟଣା ID',
      'volunteer_consignment_live_location_hint':
          'ଆପଣ କନସାଇନମେଣ୍ଟରେ ଥିବା ବେଳେ, ମାନଚିତ୍ର ଓ ETA ସଠିକ୍ ରଖିବାକୁ ଆପଣଙ୍କ ଲାଇଭ୍ ସ୍ଥାନ ଏହି ଘଟଣା ସହ ସେୟାର୍ ହୁଏ।',
      'volunteer_consignment_low_power_label': 'ଲୋ ପାୱାର',
      'volunteer_consignment_normal_gps_label': 'ସାଧାରଣ GPS',
      'bridge_card_incident_id_missing': 'ଘଟଣା ID ନାହିଁ।',
      'bridge_card_ptt_only_snackbar':
          'ଅପରେସନ୍ କନସୋଲ୍ ଶିକାରର କଣ୍ଠ Firebase PTT ମାଧ୍ୟମରେ ପଠାଇଲା। WebRTC ବ୍ରିଜ୍ ଯୋଗଦାନ ନିଷ୍କ୍ରିୟ।',
      'bridge_card_ptt_only_banner':
          'କନସୋଲ୍ Firebase PTT ମାଧ୍ୟମରେ କଣ୍ଠ ପଠାଇଲା — ଏହି ଫ୍ଲିଟ୍ ପାଇଁ LiveKit ବ୍ରିଜ୍ ଯୋଗଦାନ ନିଷ୍କ୍ରିୟ।',
      'bridge_card_connected_snackbar': 'ଭଏସ୍ ଚ୍ୟାନେଲ୍ ସହ ସଂଯୁକ୍ତ।',
      'bridge_card_could_not_join': 'ଯୋଗଦେବାକୁ ଅସମର୍ଥ: {err}',
      'bridge_card_voice_channel_title': 'ଭଏସ୍ ଚ୍ୟାନେଲ୍',
      'bridge_card_calm_disclaimer':
          'ଶାନ୍ତ ରୁହନ୍ତୁ ଏବଂ ସ୍ପଷ୍ଟ କହନ୍ତୁ। ସ୍ଥିର ସ୍ୱର ଶିକାର ଏବଂ ଅନ୍ୟ ସହାୟକଙ୍କୁ ସାହାଯ୍ୟ କରେ। ଚିତ୍କାର କରନ୍ତୁ ନାହିଁ କିମ୍ବା ଶବ୍ଦଗୁଡ଼ିକୁ ଶୀଘ୍ର କହନ୍ତୁ ନାହିଁ।',
      'bridge_card_cancel': 'ରଦ୍ଦ',
      'bridge_card_join_voice': 'ଭଏସ୍‌ରେ ଯୋଗଦିଅନ୍ତୁ',
      'bridge_card_voice_connected': 'ଭଏସ୍ ସଂଯୁକ୍ତ',
      'bridge_card_in_channel': 'ଚ୍ୟାନେଲ୍‌ରେ {n} ଜଣ',
      'bridge_card_transmitting': 'ପ୍ରସାରଣ ହେଉଛି…',
      'bridge_card_hold_to_talk': 'କହିବାକୁ ଧରିରଖନ୍ତୁ',
      'bridge_card_disconnect': 'ଡିସକନେକ୍ଟ',
      'vol_ems_banner_en_route': 'ଆମ୍ବୁଲାନ୍ସ ଘଟଣାସ୍ଥଳକୁ ଯାଉଛି',
      'vol_ems_banner_on_scene': 'ଆମ୍ବୁଲାନ୍ସ ସ୍ଥାନରେ (~200 ମିଟର)',
      'vol_ems_banner_returning': 'ଆମ୍ବୁଲାନ୍ସ ଡାକ୍ତରଖାନାକୁ ଫେରୁଛି',
      'vol_ems_banner_complete': 'ପ୍ରତିକ୍ରିୟା ସମାପ୍ତ · ଆମ୍ବୁଲାନ୍ସ ଷ୍ଟେସନରେ',
      'vol_ems_banner_complete_with_cycle':
          'ପ୍ରତିକ୍ରିୟା ସମାପ୍ତ · ଆମ୍ବୁଲାନ୍ସ ଷ୍ଟେସନରେ · ମୋଟ ଚକ୍ର {m}ମି {s}ସେ',
      'vol_tooltip_lifeline_first_aid':
          'ଲାଇଫ୍‌ଲାଇନ୍ — ପ୍ରାଥମିକ ଚିକିତ୍ସା ଗାଇଡ୍ (ପ୍ରତିକ୍ରିୟାରେ ରହିଥାଏ)',
      'vol_tooltip_exit_mission': 'ମିସନ୍ ବାହାର',
      'vol_low_power_tracking_hint':
          'ଲୋ-ପାୱାର୍ ଟ୍ରାକିଂ: ଆମେ ଆପଣଙ୍କ ସ୍ଥାନକୁ କମ୍ ଥର, ବଡ଼ ଗତି ପରେ ହିଁ ସିଙ୍କ୍ କରୁ। ଡିସ୍ପାଚ୍ ଆପଣଙ୍କ ଶେଷ ବିନ୍ଦୁକୁ ଦେଖେ।',
      'vol_marker_you': 'ଆପଣ',
      'vol_marker_active_unit': 'ସକ୍ରିୟ ୟୁନିଟ୍',
      'vol_marker_practice_incident': 'ଅଭ୍ୟାସ ଘଟଣା',
      'vol_marker_accident_scene': 'ଦୁର୍ଘଟଣା ସ୍ଥାନ',
      'vol_marker_training_pin': 'ତାଲିମ ପିନ୍ — ପ୍ରକୃତ SOS ନୁହେଁ',
      'vol_marker_high_severity': 'GITM କଲେଜ - ଉଚ୍ଚ ଗମ୍ଭୀରତା',
      'vol_marker_accepted_hospital': 'ସ୍ୱୀକୃତ: {hospital}',
      'vol_marker_trying_hospital': 'ଚେଷ୍ଟା: {hospital}',
      'vol_marker_ambulance_on_scene': 'ଆମ୍ବୁଲାନ୍ସ ସ୍ଥାନରେ!',
      'vol_marker_ambulance_en_route': 'ଆମ୍ବୁଲାନ୍ସ ପଥରେ',
      'vol_badge_at_scene_pin': 'ସ୍ଥାନ ପିନରେ',
      'vol_badge_in_5km_zone': '5 କିମି ଅଞ୍ଚଳରେ',
      'vol_badge_en_route': 'ପଥରେ',
    },

    // ── Urdu (اردو) ────────────────────────────────────────────────────────
    'ur': {
      'app_name': 'EmergencyOS',
      'profile_title': 'پروفائل اور میڈیکل آئی ڈی',
      'language': 'زبان',
      'save_medical_profile': 'طبی پروفائل محفوظ کریں',
      'critical_medical_info': 'اہم طبی معلومات',
      'emergency_contacts': 'ایمرجنسی رابطے',
      'golden_hour_details': 'گولڈن آور تفصیلات',
      'sos_lock': 'SOS لاک',
      'top_life_savers': 'سرفہرست جان بچانے والے',
      'lives_saved': 'بچائی گئی جانیں',
      'active_alerts': 'فعال الرٹس',
      'rank': 'درجہ',
      'on_duty': 'ڈیوٹی پر',
      'standby': 'اسٹینڈبائی',
      'sos': 'SOS',
      'call_now': 'ابھی کال کریں',
      'quick_guide': 'فوری رہنمائی',
      'detailed_instructions': 'تفصیلی ہدایات',
      'red_flags': 'خطرے کے اشارے',
      'cautions': 'احتیاطیں',
      'voice_walkthrough': 'وائس رہنمائی',
      'playing': 'چل رہا ہے...',
      'swipe_next_guide': 'اگلی رہنمائی کے لیے سوائپ کریں',
      'watch_video_guide': 'مکمل ویڈیو گائیڈ دیکھیں',
      'emergency_grid_scan': 'ایمرجنسی گرڈ سکین',
      'area_telemetry': 'علاقائی ٹیلی میٹری اور خطرے کا اشاریہ',
      'report_hazard': 'خطرے کی اطلاع دیں',
      'todays_duty': 'آج کی ڈیوٹی',
      'blood_type': 'خون کا گروپ',
      'allergies': 'الرجی',
      'medical_conditions': 'طبی حالت',
      'contact_name': 'بنیادی رابطے کا نام',
      'contact_phone': 'بنیادی رابطے کا فون',
      'relationship': 'رشتہ',
      'medications': 'موجودہ ادویات',
      'organ_donor': 'عضو عطیہ کی حیثیت',
      'good_morning': 'صبح بخیر،',
      'good_afternoon': 'دوپہر بخیر،',
      'good_evening': 'شام بخیر،',
      'hospitals': 'ہسپتال',
      'visual_walkthrough': 'بصری رہنمائی',
      'lifeline': 'لائف لائن',
      'nav_home': 'ہوم',
      'nav_map': 'نقشہ',
      'nav_grid': 'گرڈ',
      'nav_profile': 'پروفائل',
      'map_caching_offline_pct': 'آف لائن کے لیے علاقہ کیش ہو رہا ہے — {pct}%',
      'map_drill_practice_banner':
          'مشق گرڈ: پلسنگ پن = ڈیمو فعال الرٹس۔ پرتوں کے لیے نقشہ فلٹر — حقیقی ڈیٹا نہیں۔',
      'map_recenter_tooltip': 'دوبارہ مرکز میں لائیں',
      'map_legend_hospital': 'ہسپتال',
      'map_legend_live_sos_history': 'لائیو SOS / تاریخ',
      'map_legend_past_this_hex': 'گزشتہ (یہ ہیکس)',
      'map_legend_in_area': 'علاقے میں {n}',
      'map_legend_in_cell': 'سیل میں {n}',
      'map_legend_volunteers_on_duty': 'ڈیوٹی پر رضاکار',
      'map_legend_volunteers_in_grid': 'گرڈ میں {n}',
      'map_legend_responder_scene': 'جواب دہندہ → منظر',
      'map_responder_routes_one': '{n} راستہ',
      'map_responder_routes_many': '{n} راستے',
      'map_filters_title': 'نقشہ فلٹر',
      'step_prefix': 'قدم',
      'highlights_steps': 'ایک ایک کر کے قدم دکھاتا ہے',
      'offline_mode': 'آف لائن — نیٹ ورک منقطع',
      'volunteer': 'رضاکار',
      'unranked': 'درجہ نہیں',
      'live': 'لائیو',
      'you': 'آپ',
      'saved': 'بچائے',
      'xp_responses': 'XP · {0} جوابات',
      'duty_monitoring': 'جب آپ ڈیوٹی پر ہیں تو SOS پاپ اپ آن ہیں۔',
      'turn_on_duty_msg': 'SOS پاپ اپ حاصل کرنے کے لیے ڈیوٹی آن کریں۔',
      'on_duty_snack': 'ڈیوٹی پر — آپ کے علاقے میں واقعات کی نگرانی...',
      'off_duty_snack': 'اسٹینڈبائی — ڈیوٹی سیشن ریکارڈ ہوا۔',
      'leaderboard_offline': 'لیڈربورڈ آف لائن',
      'leaderboard_offline_sub': 'سنک رکی۔ کیش سکور۔',
      'set_sos_pin_first': 'پہلے SOS پن سیٹ کریں',
      'set_pin_safety_msg': 'حفاظت کے لیے، SOS بنانے سے پہلے پن سیٹ کرنا ضروری ہے۔',
      'set_pin_now': 'ابھی پن سیٹ کریں',
      'later': 'بعد میں',
      'sos_screen_title': 'SOS',
      'sos_hold_banner': 'بھیجنے کے لیے 3 سیکنڈ دبائے رکھیں۔',
      'sos_hold_button': 'SOS بھیجنے کے لیے دبائے رکھیں',
      'sos_semantics_hold_hint': 'SOS۔ بھیجنے کے لیے تین سیکنڈ دبائے رکھیں۔',
      'home_duty_heading': 'آج کی ڈیوٹی',
      'home_duty_progress': '{done}/{total} مکمل',
      'home_map_semantics': 'آپ کا علاقہ اور مقام دکھانے والا نقشہ',
      'home_recenter_map': 'نقشہ اپنے مقام پر مرکز کریں',
      'home_sos_large_fab_hint': 'ایمرجنسی الرٹ کے لیے SOS الٹی گنتی کھولیں',
      'home_sos_cancelled_snack': 'SOS منسوخ۔',
      'home_sos_sent_snack': 'SOS بھیجا گیا! ایمرجنسی سروسز کو مطلع کیا گیا۔',
      'quick_sos_title': 'فوری SOS',
      'quick_sos_subtitle': 'جواب دیں — تفصیلات سے مدد جلدی آتی ہے',
      'quick_sos_practice_banner':
          'مشق گائیڈڈ انٹیک — جمع کرنے سے اصلی SOS نہیں بنے گا۔',
      'quick_sos_section_what': 'ایمرجنسی کیا ہے؟',
      'quick_sos_section_someone_else': 'کیا آپ کسی اور کے لیے SOS چلا رہے ہیں؟',
      'quick_sos_send_now': 'ابھی SOS بھیجیں',
      'quick_sos_select_first': 'ایمرجنسی منتخب کریں اور تصدیق کریں',
      'quick_sos_section_victim': 'متاثرہ کی حالت',
      'quick_sos_victim_subtitle': 'جواب دہندگان کو صحیح سامان تیار کرنے میں مدد',
      'quick_sos_section_people': 'کتنے لوگوں کو مدد درکار؟',
      'quick_sos_yes_someone_else': 'ہاں — کسی اور کے لیے',
      'quick_sos_no_for_me': 'نہیں — میرے لیے',
      'quick_sos_other_hint': 'اپنی صورت حال مختصراً بیان کریں...',
      'quick_sos_close': 'فوری SOS بند کریں',
      'quick_sos_drill_submit_disabled':
          'مشق: جمع کرانا غیر فعال۔ ڈرل کے لیے ہوم پر سرخ SOS 3 سیکنڈ دبائیں۔',
      'quick_sos_failed': 'SOS ناکام: {detail}',
      'quick_sos_could_not_start': 'SOS شروع نہیں ہو سکا۔ دوبارہ کوشش کریں۔',
      'quick_sos_victim_conscious_q': 'کیا شخص ہوش میں ہے؟',
      'sos_are_you_conscious':
          'کیا آپ ہوش میں ہیں؟ براہ کرم ہاں یا نہیں جواب دیں۔',
      'sos_tts_opening_guidance':
          'آپ کا SOS فعال ہے۔ مدد آ رہی ہے۔ بولے گئے اشاروں کی پیروی کریں اور جواب دینے کے لیے ٹیپ کریں۔',
      'sos_interview_q1_prompt': 'کیا ہو رہا ہے؟ (ایمرجنسی کی قسم)',
      'sos_interview_q2_prompt': 'کیا آپ محفوظ ہیں؟ کتنا سنگین؟',
      'sos_interview_q3_prompt': 'کتنے لوگ شامل ہیں؟',
      'sos_chip_cat_accident': 'حادثہ',
      'sos_chip_cat_medical': 'طبی',
      'sos_chip_cat_hazard': 'خطرہ (آگ، ڈوبنا وغیرہ)',
      'sos_chip_cat_assault': 'حملہ',
      'sos_chip_cat_other': 'دیگر',
      'sos_chip_safe_critical': 'سنگین (جان لیوا)',
      'sos_chip_safe_injured': 'زخمی مگر مستحکم',
      'sos_chip_safe_danger': 'زخمی نہیں مگر خطرے میں',
      'sos_chip_safe_safe_now': 'اب محفوظ',
      'sos_chip_people_me': 'صرف میں',
      'sos_chip_people_two': 'دو',
      'sos_chip_people_many': 'دو سے زیادہ',
      'sos_tts_interview_saved':
          'متاثرہ انٹرویو ڈیٹا محفوظ۔ جواب دہندگان کے پاس تفصیل ہے۔',
      'sos_tts_map_routes':
          'نقشہ ٹیب کھولیں: سرخ مقررہ ہسپتال کا سڑک کا راستہ یا قریبی راستہ؛ سبز رضاکار کا راستہ۔ ایمرجنسی وائس چینل پر رہیں۔',
      'sos_tts_emergency_contacts_on_file':
          'Your emergency contact from your profile is attached to this SOS. SMS updates may be sent when that option is enabled.',
      'sos_tts_conscious_no_answer_attempt':
          'کوئی جواب نہیں۔ ہوش کی جانچ {max} میں سے {n}۔ ایک منٹ بعد پھر پوچھیں گے۔',
      'voice_volunteer_accepted':
          'رضاکار نے قبول کیا۔ مدد راستے میں ہے۔',
      'voice_ambulance_dispatched_eta':
          'ایمبولینس روانہ۔ متوقع آمد: {eta}۔',
      'voice_police_dispatched_eta':
          'پولیس روانہ۔ متوقع آمد: {eta}۔',
      'voice_ambulance_on_scene_victim':
          'ایمبولینس موقع پر ہے — آپ سے تقریباً دو سو میٹر کے فاصلے پر۔',
      'voice_ambulance_on_scene_volunteer':
          'ایمبولینس موقع پر ہے — واقعے کی جگہ سے تقریباً دو سو میٹر کے اندر۔',
      'voice_ambulance_returning': 'ایمبولینس ہسپتال واپس جا رہی ہے۔',
      'voice_response_complete_station':
          'جواب مکمل۔ ایمبولینس اسٹیشن پر۔',
      'voice_response_complete_cycle':
          'جواب مکمل۔ ایمبولینس اسٹیشن پر۔ کل سائیکل {minutes} منٹ {seconds} سیکنڈ۔',
      'voice_volunteers_on_scene_count':
          '{n} رضاکار اب موقع پر ہیں۔',
      'voice_one_volunteer_on_scene': 'ایک رضاکار موقع پر ہے۔',
      'voice_ptt_joined_comms': '{who} نے آواز کے رابطے میں شمولیت اختیار کی۔',
      'voice_tts_unavailable_banner':
          'آواز کی رہنمائی دستیاب نہیں — براہ کرم سکرین پر متن پڑھیں۔',
      'language_picker_title': 'زبان',
      'volunteer_victim_medical_card': 'متاثرہ میڈیکل کارڈ',
      'volunteer_dispatch_milestone_title': 'ڈسپیچ اپ ڈیٹس',
      'volunteer_dispatch_milestone_hospital': 'ہسپتال نے قبول کیا: {hospital}',
      'volunteer_dispatch_milestone_unit': 'ایمبولینس یونٹ: {unit}',
      'volunteer_dispatch_milestone_crew_pending': 'ایمبولینس عملہ: ہم آہنگی…',
      'volunteer_dispatch_milestone_en_route': 'ایمبولینس راستے میں',
      'volunteer_triage_qr_report_title': 'QR یا ٹیپ رپورٹ',
      'volunteer_triage_qr_report_subtitle':
          'ہینڈ آف کے لیے کوڈ اسکین کریں یا واقعے کی رپورٹ محفوظ کرنے کے لیے ٹیپ کریں۔',
      'volunteer_triage_show_qr': 'QR دکھائیں',
      'volunteer_triage_tap_report': 'رپورٹ',
      'volunteer_triage_qr_title': 'واقعہ ہینڈ آف QR',
      'volunteer_triage_qr_body': 'ساختی ڈیٹا کے لیے عملے یا EMS کے ساتھ شیئر کریں۔',
      'volunteer_triage_report_saved': 'رپورٹ اس واقعے کے تحت محفوظ ہو گئی۔',
      'volunteer_triage_report_failed': 'رپورٹ محفوظ نہیں ہو سکی: ',
      'volunteer_victim_medical_offline_hint': 'SOS پیکٹ سے — آف لائن کیش سے۔',
      'volunteer_victim_consciousness_title': 'ہوش',
      'volunteer_victim_three_questions': 'ابتدائی جوابات',
      'volunteer_major_updates_log': 'صرف اہم اپ ڈیٹس',
      'volunteer_dispatch_escalating_tier_trying_hospital':
          'ٹیئر {tier} تک بڑھا رہے ہیں۔ ہسپتال {hospital} آزما رہے ہیں۔',
      'volunteer_dispatch_trying_hospital': 'ہسپتال {hospital} آزما رہے ہیں۔',
      'volunteer_dispatch_hospital_accepted':
          '{hospital} نے ایمرجنسی قبول کی۔ ایمبولینس ہم آہنگی جاری ہے۔',
      'volunteer_dispatch_all_hospitals_notified':
          'تمام ہسپتالوں کو مطلع کیا۔ ایمرجنسی خدمات تک بڑھا رہے ہیں۔',
      'sos_dispatch_alerting_nearest_trying':
          'آپ کے علاقے کے قریب ترین ہسپتال کو الرٹ کر رہے ہیں۔ {hospital} آزما رہے ہیں۔',
      'sos_dispatch_escalating_tier_trying':
          'کوئی جواب نہیں۔ ٹیئر {tier} تک بڑھا رہے ہیں۔ {hospital} آزما رہے ہیں۔',
      'sos_dispatch_retry_previous_trying':
          'پچھلے ہسپتال سے کوئی جواب نہیں۔ {hospital} آزما رہے ہیں۔',
      'sos_dispatch_all_hospitals_call_112':
          'تمام ہسپتالوں کو مطلع کیا۔ ایمرجنسی خدمات کے لیے براہ کرم 112 پر کال کریں۔',
      'quick_sos_victim_breathing_q': 'کیا شخص سانس لے رہا ہے؟',
      'quick_sos_label_yes': 'ہاں',
      'quick_sos_label_no': 'نہیں',
      'quick_sos_label_unsure': 'یقین نہیں',
      'quick_sos_person': 'شخص',
      'quick_sos_people': 'افراد',
      'quick_sos_people_three_plus': '۳+',
      'login_tagline': 'جانیں بچائیں',
      'login_subtitle':
          'ایمرجنسی رپورٹ کریں، رضاکاروں سے رابطہ کریں، گولڈن آور میں جانیں بچائیں۔',
      'login_continue_google': 'Google سے جاری رکھیں',
      'login_continue_phone': 'فون سے جاری رکھیں',
      'login_send_code': 'تصدیقی کوڈ بھیجیں',
      'login_verify_login': 'تصدیق کریں اور لاگ ان',
      'login_phone_label': 'فون نمبر',
      'login_phone_hint': '+923001234567',
      'login_otp_label': 'تصدیقی کوڈ (OTP)',
      'login_back_options': 'اختیارات پر واپس',
      'login_change_phone': 'فون نمبر بدلیں',
      'login_drill_mode': 'ڈرل موڈ',
      'login_drill_subtitle': 'مشق کے لیے ٹیپ — کوئی حقیقی SOS نہیں',
      'login_drill_semantics': 'ڈرل موڈ، حقیقی ایمرجنسی کے بغیر مشق',
      'login_practise_victim': 'متاثرہ کے طور پر مشق',
      'login_practise_volunteer': 'رضاکار کے طور پر مشق',
      'login_admin_note':
          'ماسٹر کنسول: الگ اکاؤنٹ نہیں — نیچے ٹیپ کریں۔ لاگ ان نہ ہونے پر ہلکا گمنام سیشن۔',
      'login_ems_dashboard': 'EMS ڈیش بورڈ',
      'login_emergency_operator': 'ایمرجنسی سروس آپریٹر لاگ ان',
      'ai_assist_practice_banner':
          'مشق Lifeline — حقیقی ڈسپیچ پر کچھ نہیں جاتا۔',
      'ai_assist_rail_semantics': 'Lifeline سطح {n}: {title}',
      'ai_assist_emergency_toggle_on': 'ایمرجنسی موڈ آن، فوری رہنمائی',
      'ai_assist_emergency_toggle_off': 'ایمرجنسی موڈ آف',
      'dashboard_exit_drill_title': 'ڈرل موڈ سے باہر؟',
      'dashboard_exit_drill_body':
          'آپ مشق سیشن سے سائن آؤٹ ہو کر لاگ ان پر واپس جائیں گے۔',
      'dashboard_back_login_tooltip': 'لاگ ان پر واپس',
      'dashboard_exit_drill_confirm': 'باہر نکلیں',
      'sos_active_title_big': 'ایکٹو SOS',
      'sos_active_help_coming': 'مدد آ رہی ہے۔ پرسکون رہیں۔',
      'sos_active_badge_waiting': 'انتظار',
      'sos_active_badge_en_route_count': '{n} راستے میں',
      'sos_active_mini_ambulance': 'ایمبولینس',
      'sos_active_mini_on_scene': 'جائے وقوعہ پر',
      'sos_active_mini_status': 'حالت',
      'sos_active_volunteers_count_short': '{n} رضاکار',
      'sos_active_dash': '—',
      'sos_active_all_hospitals_notified_title':
          'تمام ہسپتالوں کو مطلع کیا',
      'sos_active_all_hospitals_notified_subtitle':
          'وقت پر کسی ہسپتال نے قبول نہیں کیا۔ ڈسپیچ ایمرجنسی سروسز تک بڑھا رہا ہے۔',
      'sos_active_position_refresh_note':
          'بیٹری بچانے کے لیے SOS کے دوران آپ کا مقام تقریباً ہر 45 سیکنڈ میں ریفریش ہوتا ہے۔ ایپ کھلی رکھیں اور ممکن ہو تو چارج پر لگائیں۔',
      'sos_active_mic_active': 'مائیک · فعال',
      'sos_active_mic_active_detail':
          'لائیو چینل آپ کا مائیکروفون وصول کر رہا ہے۔',
      'sos_active_mic_standby': 'مائیک · اسٹینڈ بائی',
      'sos_active_mic_standby_detail': 'وائس چینل کا انتظار…',
      'sos_active_mic_connecting': 'مائیک · منسلک ہو رہا ہے',
      'sos_active_mic_connecting_detail':
          'ایمرجنسی وائس چینل میں شامل ہو رہا ہے…',
      'sos_active_mic_reconnecting': 'مائیک · دوبارہ کنکٹ',
      'sos_active_mic_reconnecting_detail':
          'لائیو آڈیو بحال ہو رہا ہے…',
      'sos_active_mic_failed': 'مائیک · رکاوٹ',
      'sos_active_mic_failed_detail':
          'وائس چینل دستیاب نہیں۔ اوپر RETRY استعمال کریں۔',
      'sos_active_mic_ptt_only': 'مائیک · واقعہ چینل',
      'sos_active_mic_ptt_only_detail':
          'آپریشنز کنسول نے Firebase PTT کے ذریعے آواز روٹ کی۔ جواب دہندگان تک پہنچنے کے لیے براڈ کاسٹ دبائے رکھیں۔',
      'sos_active_mic_interrupted': 'مائیک · روکا گیا',
      'sos_active_mic_interrupted_detail':
          'ایپ آڈیو پروسیس کرتے وقت مختصر وقفہ۔',
      'sos_active_consciousness_note':
          'ہوش کی جانچ کا جواب ہاں یا نہیں میں دیں؛ دیگر پرامپٹ اسکرین کے اختیارات استعمال کرتے ہیں۔',
      'sos_active_live_updates_header': 'لائیو اپڈیٹس',
      'sos_active_live_updates_subtitle':
          'ڈسپیچ، رضاکار اور ڈیوائس',
      'sos_active_live_tag': 'لائیو',
      'sos_active_activity_log': 'سرگرمی لاگ',
      'sos_active_header_stat_coordinating_crew': 'ٹیم رابطہ',
      'sos_active_header_stat_coordinating': 'رابطہ',
      'sos_active_header_stat_en_route': 'راستے میں',
      'sos_active_header_stat_route_min': '~{n} منٹ',
      'sos_active_live_sos_is_live_title': 'SOS لائیو ہے',
      'sos_active_live_sos_is_live_detail':
          'آپ کا مقام اور طبی فلیگ ایمرجنسی نیٹ ورک پر ہیں۔',
      'sos_active_live_volunteers_notified_title':
          'رضاکاروں کو مطلع کیا',
      'sos_active_live_volunteers_notified_detail':
          'قریبی رضاکار یہ واقعہ ریئل ٹائم میں وصول کرتے ہیں۔',
      'sos_active_live_bridge_connected_title':
          'ایمرجنسی وائس برج جڑا',
      'sos_active_live_bridge_connected_detail':
          'ڈسپیچ ڈیسک اور جواب دہندگان یہ چینل سن سکتے ہیں۔',
      'sos_active_live_ptt_title': 'Firebase PTT کے ذریعے آواز',
      'sos_active_live_ptt_detail':
          'اس فلیٹ کے لیے لائیو WebRTC برج بند ہے۔ آواز اور متنی اپڈیٹس کے لیے براڈ کاسٹ استعمال کریں۔',
      'sos_active_live_contacts_notified_title':
          'ایمرجنسی رابطوں کو مطلع کیا',
      'sos_active_live_hospital_accepted_title': 'ہسپتال نے قبول کیا',
      'sos_active_live_ambulance_unit_assigned_title':
          'ایمبولینس یونٹ تفویض',
      'sos_active_live_ambulance_unit_assigned_subtitle': 'یونٹ {unit}',
      'sos_active_live_ambulance_en_route_title': 'ایمبولینس راستے میں',
      'sos_active_live_ambulance_en_route_subtitle': 'EMS ETA · {eta}',
      'sos_active_live_ambulance_en_route_default_eta': 'راستے میں',
      'sos_active_live_ambulance_en_route_route_eta': '~{n} منٹ (روٹ)',
      'sos_active_live_ambulance_coordination_title': 'ایمبولینس ہم آہنگی',
      'sos_active_live_ambulance_coordination_pending':
          'ہسپتال نے قبول کیا — ایمبولینس آپریٹرز کو مطلع کیا جا رہا ہے۔',
      'sos_active_live_ambulance_coordination_arranging':
          'ایمبولینس عملے کا اہتمام — یونٹ راستے میں ہو تو منٹ ETA۔',
      'sos_active_live_responder_status_title': 'جواب دہندہ کی حالت',
      'sos_active_live_volunteer_accepted_single_title':
          'رضاکار نے قبول کیا',
      'sos_active_live_volunteer_accepted_many_title':
          'رضاکاروں نے قبول کیا',
      'sos_active_live_volunteer_accepted_single_detail':
          'ایک جواب دہندہ تفویض ہے اور آپ کی طرف آ رہا ہے۔',
      'sos_active_live_volunteer_accepted_many_detail':
          '{n} جواب دہندگان اس SOS کے لیے تفویض ہیں۔',
      'sos_active_live_volunteer_on_scene_single_title':
          'رضاکار جائے وقوعہ پر پہنچ گیا',
      'sos_active_live_volunteer_on_scene_many_title':
          'رضاکار جائے وقوعہ پر',
      'sos_active_live_volunteer_on_scene_single_detail':
          'کوئی آپ کے ساتھ یا آپ کے پن پر ہے۔',
      'sos_active_live_volunteer_on_scene_many_detail':
          '{n} جواب دہندگان جائے وقوعہ پر نشان زد۔',
      'sos_active_live_responder_location_title':
          'لائیو جواب دہندہ کا مقام',
      'sos_active_live_responder_location_detail':
          'تفویض کردہ رضاکار کا GPS نقشے پر اپڈیٹ ہو رہا ہے۔',
      'sos_active_live_professional_dispatch_title':
          'پیشہ ور ڈسپیچ فعال',
      'sos_active_live_professional_dispatch_detail':
          'مربوط خدمات اس واقعے پر کام کر رہی ہیں۔',
      'sos_active_ambulance_200m_detail':
          'ایمبولینس جائے وقوعہ پر — تقریباً 200 میٹر کے اندر۔',
      'sos_active_ambulance_200m_semantic_label':
          'ایمبولینس تقریباً دو سو میٹر کے اندر جائے وقوعہ پر',
      'sos_active_bridge_channel_on_suffix': ' · {n} چینل پر',
      'sos_active_bridge_channel_voice': 'ایمرجنسی وائس چینل',
      'sos_active_bridge_channel_ptt': 'ایمرجنسی چینل · Firebase PTT',
      'sos_active_bridge_channel_failed':
          'ایمرجنسی چینل · دوبارہ کوشش کریں',
      'sos_active_bridge_channel_connecting':
          'ایمرجنسی چینل · منسلک ہو رہا ہے',
      'sos_active_dispatch_contact_hospitals_default':
          'ہم آپ کے مقام اور ایمرجنسی قسم کی بنیاد پر قریبی ہسپتالوں سے رابطہ کر رہے ہیں۔',
      'sos_active_dispatch_ambulance_crew_notified_title':
          'ایمبولینس عملے کو مطلع کیا',
      'sos_active_dispatch_ambulance_crew_notified_subtitle':
          'پارٹنر ہسپتال نے آپ کا کیس قبول کیا۔ ایمبولینس آپریٹرز کو مطلع کیا جا رہا ہے۔',
      'sos_active_dispatch_ambulance_confirmed_title':
          'ایمبولینس تصدیق',
      'sos_active_dispatch_ambulance_confirmed_subtitle_unit':
          'یونٹ {unit} آپ کی طرف آ رہا ہے۔ وہاں رہیں جہاں جواب دہندگان پہنچ سکیں۔',
      'sos_active_dispatch_ambulance_confirmed_subtitle_generic':
          'ایک ایمبولینس آپ کی طرف آ رہی ہے۔ وہاں رہیں جہاں جواب دہندگان پہنچ سکیں۔',
      'sos_active_dispatch_ambulance_handoff_delayed_title':
          'ایمبولینس حوالگی میں تاخیر',
      'sos_active_dispatch_ambulance_handoff_delayed_subtitle':
          'ہسپتال نے قبول کیا، لیکن وقت پر کوئی ایمبولینس عملہ تصدیق نہیں ہوا۔ ڈسپیچ بڑھا رہا ہے — ضرورت ہو تو 112 پر کال کریں۔',
      'sos_active_dispatch_pending_title_trying': 'کوشش: {hospital}',
      'sos_active_dispatch_pending_subtitle_waiting':
          '{tier} · ہسپتال کے جواب کا انتظار۔',
      'sos_active_dispatch_accepted_title': '{hospital} نے قبول کیا',
      'sos_active_dispatch_accepted_subtitle':
          'ایمبولینس ڈسپیچ کی ہم آہنگی کی جا رہی ہے۔',
      'sos_active_dispatch_exhausted_title':
          'تمام ہسپتالوں کو مطلع کیا',
      'sos_active_dispatch_exhausted_subtitle':
          'وقت پر کسی ہسپتال نے قبول نہیں کیا۔ ڈسپیچ ایمرجنسی سروسز تک بڑھا رہا ہے۔',
      'sos_active_dispatch_generic_title': 'ہسپتال ڈسپیچ',
      'sos_active_dispatch_generic_subtitle': '{hospital} · {status}',
      'volunteer_bridge_voice_channel_title': 'ایمرجنسی وائس چینل',
      'volunteer_bridge_join_hint_incident':
          'شامل ہونے کے لیے یہ واقعہ استعمال ہوتا ہے: آپ کا نمبر میچ کرے تو ایمرجنسی رابطہ؛ ورنہ منظور شدہ رضاکار۔',
      'volunteer_bridge_join_hint_elite':
          'آپ منظور شدہ جواب دہندہ ہوں تو شامل ہونا آپ کی ایلیٹ رسائی استعمال کرتا ہے؛ ورنہ نمبر میچ کرے تو رابطہ۔',
      'volunteer_bridge_join_hint_desk':
          'آپ اپنی پروفائل پر ایمرجنسی سروسز ڈیسک کے طور پر ڈسپیچ کے طور پر شامل ہوتے ہیں۔',
      'volunteer_bridge_join_voice_btn': 'وائس میں شامل ہوں',
      'volunteer_bridge_connecting_btn': 'منسلک ہو رہا ہے…',
      'volunteer_bridge_incident_id_hint': 'واقعہ ID',
      'volunteer_consignment_live_location_hint':
          'آپ کنسائنمنٹ پر ہوں تو، نقشہ اور ETA درست رکھنے کے لیے آپ کا لائیو مقام اس واقعے سے شیئر کیا جاتا ہے۔',
      'volunteer_consignment_low_power_label': 'لو پاور',
      'volunteer_consignment_normal_gps_label': 'عمومی GPS',
      'bridge_card_incident_id_missing': 'واقعے کی ID غائب ہے۔',
      'bridge_card_ptt_only_snackbar':
          'آپریشن کنسول نے متاثرہ کی آواز Firebase PTT کے ذریعے بھیجی۔ WebRTC برج میں شامل ہونا غیر فعال ہے۔',
      'bridge_card_ptt_only_banner':
          'کنسول نے Firebase PTT کے ذریعے آواز بھیجی — اس فلیٹ کے لیے LiveKit برج میں شامل ہونا غیر فعال ہے۔',
      'bridge_card_connected_snackbar': 'وائس چینل سے منسلک ہو گئے۔',
      'bridge_card_could_not_join': 'شامل نہیں ہو سکے: {err}',
      'bridge_card_voice_channel_title': 'وائس چینل',
      'bridge_card_calm_disclaimer':
          'پرسکون رہیں اور واضح طور پر بات کریں۔ مستحکم لہجہ متاثرہ اور دیگر مددگاروں کے لیے مفید ہے۔ چیخیں نہیں اور الفاظ جلدبازی میں نہ کہیں۔',
      'bridge_card_cancel': 'منسوخ',
      'bridge_card_join_voice': 'وائس میں شامل ہوں',
      'bridge_card_voice_connected': 'وائس منسلک',
      'bridge_card_in_channel': 'چینل میں {n} افراد',
      'bridge_card_transmitting': 'ترسیل جاری ہے…',
      'bridge_card_hold_to_talk': 'بات کرنے کے لیے دبائے رکھیں',
      'bridge_card_disconnect': 'منقطع',
      'vol_ems_banner_en_route': 'ایمبولینس واقعے کی جگہ کی طرف',
      'vol_ems_banner_on_scene': 'ایمبولینس موقع پر (~200 میٹر)',
      'vol_ems_banner_returning': 'ایمبولینس ہسپتال واپس جا رہی ہے',
      'vol_ems_banner_complete': 'جواب مکمل · ایمبولینس سٹیشن پر',
      'vol_ems_banner_complete_with_cycle':
          'جواب مکمل · ایمبولینس سٹیشن پر · کل سائیکل {m}منٹ {s}سیکنڈ',
      'vol_tooltip_lifeline_first_aid':
          'لائف لائن — ابتدائی طبی امداد گائیڈز (جواب پر رہتی ہیں)',
      'vol_tooltip_exit_mission': 'مشن چھوڑیں',
      'vol_low_power_tracking_hint':
          'کم پاور ٹریکنگ: ہم آپ کی پوزیشن کم بار اور صرف بڑی حرکات کے بعد سنک کرتے ہیں۔ ڈسپیچ اب بھی آپ کا آخری پوائنٹ دیکھتا ہے۔',
      'vol_marker_you': 'آپ',
      'vol_marker_active_unit': 'فعال یونٹ',
      'vol_marker_practice_incident': 'مشق واقعہ',
      'vol_marker_accident_scene': 'حادثہ مقام',
      'vol_marker_training_pin': 'تربیتی پن — حقیقی SOS نہیں',
      'vol_marker_high_severity': 'GITM کالج - اعلیٰ شدت',
      'vol_marker_accepted_hospital': 'قبول: {hospital}',
      'vol_marker_trying_hospital': 'کوشش: {hospital}',
      'vol_marker_ambulance_on_scene': 'ایمبولینس موقع پر!',
      'vol_marker_ambulance_en_route': 'ایمبولینس راستے میں',
      'vol_badge_at_scene_pin': 'مقام پن پر',
      'vol_badge_in_5km_zone': '5 کلومیٹر زون میں',
      'vol_badge_en_route': 'راستے میں',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'hi', 'ta', 'te', 'kn', 'ml', 'bn', 'mr', 'gu', 'pa', 'or', 'ur']
          .contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
