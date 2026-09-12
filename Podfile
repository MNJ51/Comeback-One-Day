platform :ios, '18.0'

target 'Comebackone day 1.2' do
  use_frameworks!
  pod 'FBAudienceNetwork'

  # Comebackone_day_1_2Tests does `@testable import Comebackone_day_1_2`,
  # which needs FBAudienceNetwork's module findable in its own search paths
  # too (AdsManager.swift imports it) — `inherit! :search_paths` gets it
  # that without actually linking/embedding the framework a second time.
  target 'Comebackone day 1.2Tests' do
    inherit! :search_paths
  end
end
