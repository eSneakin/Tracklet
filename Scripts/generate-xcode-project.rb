# Run only when intentionally regenerating the project. Uses the locally installed xcodeproj gem.
require 'xcodeproj'

root = File.expand_path('..', __dir__)
Dir.chdir(root)
project = Xcodeproj::Project.new('Tracklet.xcodeproj')
config = project.main_group.new_group('Configuration', 'Configuration')
Dir['Configuration/*'].sort.each { |path| config.new_file(File.basename(path)) }
xcconfig = config.files.find { |file| file.path == 'Tracklet.xcconfig' }

app = project.new_target(:application, 'Tracklet', :osx, '13.0')
widget = project.new_target(:app_extension, 'TrackletWidgetExtension', :osx, '14.0')
references = {}
app_group = project.main_group.new_group('Tracklet Sources')
Dir['Sources/Tracklet/**/*.swift'].sort.each do |path|
  ref = app_group.new_file(path)
  references[path] = ref
  app.source_build_phase.add_file_reference(ref)
end
widget_group = project.main_group.new_group('TrackletWidgetExtension', 'TrackletWidgetExtension')
Dir['TrackletWidgetExtension/*.swift'].sort.each do |path|
  widget.source_build_phase.add_file_reference(widget_group.new_file(File.basename(path)))
end
shared = Dir['Sources/Tracklet/Shared/*.swift'] + [
  'Sources/Tracklet/Models/PlaybackState.swift',
  'Sources/Tracklet/Models/WidgetPreferences.swift',
  'Sources/Tracklet/Theme/TrackletTheme.swift'
]
shared.sort.each { |path| widget.source_build_phase.add_file_reference(references.fetch(path)) }

resources = project.main_group.new_group('Resources', 'Resources')
icon = resources.new_file('AppIcon.icon')
icon.last_known_file_type = 'folder.iconcomposer'
app.resources_build_phase.add_file_reference(icon)
app.build_configurations.each do |configuration|
  configuration.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  configuration.build_settings.delete('ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME')
end

[[app, 'com.tracklet.app', 'Tracklet'], [widget, 'com.tracklet.app.widget', 'Widget']].each do |target, bundle, config_name|
  target.build_configurations.each do |configuration|
    configuration.base_configuration_reference = xcconfig
    configuration.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => bundle,
      'INFOPLIST_FILE' => "Configuration/#{config_name}-Info.plist",
      'CODE_SIGN_ENTITLEMENTS' => "Configuration/#{config_name}.entitlements",
      'GENERATE_INFOPLIST_FILE' => 'NO',
      'SWIFT_EMIT_LOC_STRINGS' => 'YES',
      'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks', '@executable_path/../../../../Frameworks']
    })
  end
end
widget.build_configurations.each do |configuration|
  configuration.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) WIDGET_EXTENSION'
  configuration.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  configuration.build_settings['SKIP_INSTALL'] = 'YES'
end
app.add_dependency(widget)
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(widget.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.root_object.attributes['TargetAttributes'] = {
  app.uuid => { 'SystemCapabilities' => { 'com.apple.ApplicationGroups.Mac' => { 'enabled' => 1 } } },
  widget.uuid => { 'SystemCapabilities' => { 'com.apple.ApplicationGroups.Mac' => { 'enabled' => 1 }, 'com.apple.Sandbox' => { 'enabled' => 1 } } }
}
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'Tracklet', true)
puts 'Generated Tracklet.xcodeproj (app + embedded widget; no Spotify source copied).'
