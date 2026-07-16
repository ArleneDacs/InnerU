# Creates the InnerUWatchWidget WidgetKit extension target, embeds it in
# the InnerUWatch app, and shares WatchState.swift with it.
# Run with /opt/homebrew/opt/ruby/bin/ruby. Safe to re-run (idempotent).
Dir.glob('/opt/homebrew/Cellar/cocoapods/*/libexec/gems/*/lib').each do |path|
  $LOAD_PATH.unshift(path)
end
require 'xcodeproj'

project_path = File.expand_path('../Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

if project.targets.any? { |t| t.name == 'InnerUWatchWidget' }
  puts 'InnerUWatchWidget target already exists — nothing to do.'
  exit 0
end

watch_target = project.targets.find { |t| t.name == 'InnerUWatch' }
raise 'InnerUWatch target not found' unless watch_target

widget = project.new_target(
  :app_extension, 'InnerUWatchWidget', :watchos, '10.0'
)

widget.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.valenin.inneru.watchkitapp.widget'
  # Xcodeproj's new_target does not set this; without it the product
  # path resolves to ".appex" and the build fails.
  bs['PRODUCT_NAME'] = 'InnerUWatchWidget'
  bs['INFOPLIST_FILE'] = 'InnerUWatchWidget/Info.plist'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['SDKROOT'] = 'watchos'
  bs['SUPPORTED_PLATFORMS'] = 'watchos watchsimulator'
  bs['TARGETED_DEVICE_FAMILY'] = '4'
  bs['WATCHOS_DEPLOYMENT_TARGET'] = '10.0'
  bs['SWIFT_VERSION'] = '5.0'
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  bs['DEVELOPMENT_TEAM'] = '965T647JG7'
  bs['CODE_SIGN_ENTITLEMENTS'] = 'InnerUWatchWidget/InnerUWatchWidget.entitlements'
  bs['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  bs['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  bs['SKIP_INSTALL'] = 'YES'
  bs['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks',
  ]
end

widget_group = project.main_group.find_subpath('InnerUWatchWidget', false) ||
               project.main_group.new_group('InnerUWatchWidget', 'InnerUWatchWidget')
widget_source = widget_group.new_reference('InnerUWatchWidget.swift')
widget.add_file_references([widget_source])

watch_state = project.files.find do |f|
  f.real_path.to_s.end_with?('InnerUWatch/WatchState.swift')
end
raise 'WatchState.swift not found — run add_watch_files.rb first' unless watch_state
widget.add_file_references([watch_state])

embed = watch_target.copy_files_build_phases.find do |phase|
  phase.symbol_dst_subfolder_spec == :plug_ins
end
unless embed
  embed = watch_target.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
end
build_file = embed.add_file_reference(widget.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
watch_target.add_dependency(widget)

project.save
puts 'InnerUWatchWidget target created.'
