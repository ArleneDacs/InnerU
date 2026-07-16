# Attaches Flutter's Generated.xcconfig as the base configuration of the
# watch app + widget targets so $(FLUTTER_BUILD_NAME)/$(FLUTTER_BUILD_NUMBER)
# resolve there (otherwise CFBundleVersion is empty and installd rejects
# the widget appex). Run with /opt/homebrew/opt/ruby/bin/ruby. Idempotent.
Dir.glob('/opt/homebrew/Cellar/cocoapods/*/libexec/gems/*/lib').each do |path|
  $LOAD_PATH.unshift(path)
end
require 'xcodeproj'

project_path = File.expand_path('../Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

generated = project.files.find do |f|
  f.real_path.to_s.end_with?('Flutter/Generated.xcconfig')
end
raise 'Generated.xcconfig reference not found' unless generated

%w[InnerUWatch InnerUWatchWidget].each do |name|
  target = project.targets.find { |t| t.name == name }
  raise "#{name} target not found" unless target
  target.build_configurations.each do |config|
    config.base_configuration_reference = generated
  end
end

project.save
puts 'Watch targets now inherit Flutter build versions.'
