Pod::Spec.new do |s|

# 1
s.platform = :ios
s.ios.deployment_target = '12.0'
s.name = "ScannerChekinIOS"
s.summary = "Private project from Chekin"
s.requires_arc = true

# 2
s.version = "1.1.5"

# 3
s.license = { :type => "MIT", :file => "LICENSE" }

# 4 - Replace with your name and e-mail address
s.author = { "Alejandro Ruiz" => "alejandroruizponce93@gmail.com" }

# 5 - Replace this URL with your own GitHub page's URL (from the address bar)
s.homepage = "https://github.com/alejandroruizponce/ScannerChekinIOS"

# 6 - Replace this URL with your own Git URL from "Quick Setup"
s.source = { :git => "https://github.com/alejandroruizponce/ScannerChekinIOS.git",
:tag => "#{s.version}" }

# 7
s.framework = "UIKit"
s.dependency 'EVGPUImage2'
s.dependency 'GPUImage'
s.dependency 'TesseractOCRiOS'
s.dependency 'UIImage-Resize'


# 8
s.source_files = "ScannerChekinIOS/**/*.{swift}"

# 9
# s.resources = "ScannerChekinIOS/**/*.{png,jpeg,jpg,storyboard,xib,xcassets,traineddata}"

# 10
s.swift_version = "4.2"

end
