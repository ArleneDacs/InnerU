# Adds WatchState.swift + PhoneConnector.swift to the InnerUWatch target
# and wires up its entitlements. Run with /opt/homebrew/opt/ruby/bin/ruby.
Dir.glob('/opt/homebrew/Cellar/cocoapods/*/libexec/gems/*/lib').each do |path|
  $LOAD_PATH.unshift(path)
end
require 'xcodeproj'

project_path = File.expand_path('../Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

watch_target = project.targets.find { |t| t.name == 'InnerUWatch' }
raise 'InnerUWatch target not found' unless watch_target

watch_group = project.main_group.find_subpath('InnerUWatch', false)
raise 'InnerUWatch group not found' unless watch_group

%w[WatchState.swift PhoneConnector.swift].each do |file_name|
  next if watch_group.files.any? { |f| f.path == file_name }
  file_ref = watch_group.new_reference(file_name)
  watch_target.add_file_references([file_ref])
end

watch_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] =
    'InnerUWatch/InnerUWatch.entitlements'
end

project.save
puts 'InnerUWatch target updated.'
