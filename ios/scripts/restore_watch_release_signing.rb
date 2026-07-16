# Restores manual App Store distribution signing for the watch app and
# widget Release/Profile configs (archives must sign embedded binaries
# with the same certificate class as the parent Runner app).
# Run with /opt/homebrew/opt/ruby/bin/ruby. Idempotent.
Dir.glob('/opt/homebrew/Cellar/cocoapods/*/libexec/gems/*/lib').each do |path|
  $LOAD_PATH.unshift(path)
end
require 'xcodeproj'

PROFILES = {
  'InnerUWatch' => 'InnerU Watch App Store',
  'InnerUWatchWidget' => 'InnerU Watch Widget App Store',
}.freeze

project_path = File.expand_path('../Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

PROFILES.each do |target_name, profile|
  target = project.targets.find { |t| t.name == target_name }
  raise "#{target_name} target not found" unless target

  target.build_configurations.each do |config|
    next unless %w[Release Profile].include?(config.name)

    bs = config.build_settings
    bs['CODE_SIGN_STYLE'] = 'Manual'
    bs['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
    bs['CODE_SIGN_IDENTITY[sdk=watchos*]'] = 'Apple Distribution'
    bs['DEVELOPMENT_TEAM'] = ''
    bs['DEVELOPMENT_TEAM[sdk=watchos*]'] = '965T647JG7'
    bs['PROVISIONING_PROFILE_SPECIFIER'] = ''
    bs['PROVISIONING_PROFILE_SPECIFIER[sdk=watchos*]'] = profile
    puts "#{target_name} #{config.name}: manual distribution signing (#{profile})"
  end
end

project.save
puts 'Signing restored.'
