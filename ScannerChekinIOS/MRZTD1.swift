//
//  MRZ.swift
//  PassportScanner
//
//  Copyright © 2018 Alejandro Ruiz Ponce. All rights reserved.
//


import Foundation

@objc(MRZTD1)
open class MRZTD1: MRZParser {
    // check data with https://www.icao.int/publications/Documents/9303_p5_cons_en.pdf
    
    /// Was the last scan valid. A value of 1 is for when all validations are OK
    private var _isValid: Float = 0
    
    /// Do you want to see debug messages? Set to true (see init) to see what's going on.
    private var _debug = false
    
    private var lineLen: Int = 30;
    
    /// The document type from the 1st line of the MRZ. (start 1, len 1)
    @objc public var documentType: String = ""
    /// The document sub type from the 1st line of the MRZ. (start 2, len 1)
    @objc public var documentSubType: String = ""
    /// The country code from the 1st line of the MRZ (start 3, len 3)
    @objc public var countryCode: String = ""
    /// The passport number from the 1nd line of the MRZ. (start 6, len 9)
    @objc public var passportNumber: String = ""
    /// Check digit start 15, len 1 - validating the passportNumber
    private var passportNumberIsValid = false
    
    
    /// The date of birth from the 2nd line of the MRZ (start 1, len 6)
    @objc public var dateOfBirth: Date?
    /// start 7, len 1 - validating the dateOfBirth
    private var dateOfBirthIsValid = false
    /// The sex from the 2nd line of the MRZ. (start 8, len 1)
    @objc public var sex: String = ""
    /// The expiration date from the 2nd line of the MRZ. (start 9, len 6)
    @objc public var expirationDate: Date?
    /// start 15, len 1 - validating the expirationDate
    private var expirationDateIsValid = false
    /// The nationality from the 2nd line of the MRZ. (start 16, len 3)
    @objc public var nationality: String = ""
    // start 30, len 1 - validating line 1 and 2
    private var dataIsValid = false
    
    
    /// The last name from the 1st line of the MRZ (start 1, len 30, until first <<)
    @objc public var lastName: String = ""
    /// The firstname from the 1st line of the MRZ (start first << len 30)
    @objc public var firstName: String = ""
    
    
    
    /**
     Convenience method for getting all data in a dictionary
     
     :returns: Return all fields in a dictionary
     */
    @objc public override func data() -> Dictionary<String, Any> {
        return ["documentType"    : documentType,
                "documentSubType" : documentSubType,
                "countryCode"     : countryCode,
                "IDNumber"  : passportNumber,
                "dateOfBirth"     : MRZTD1.stringFromDate(dateOfBirth),
                "sex"             : sex,
                "expirationDate"  : MRZTD1.stringFromDate(expirationDate),
                "nationality"     : nationality,
                "lastName"        : lastName,
                "firstName"       : firstName]
    }
    
    /**
     Get the description of the MRZ
     
     :returns: a string with all fields plus field name (each field on a new line)
     */
    @objc open override var description: String {
        get {
            return self.data().map {"\($0) = \($1)"}.reduce("") {"\($0)\n\($1)"}
        }
    }
    
    /**
     Initiate the MRZ object with the scanned data.
     
     :param: scan  the scanned string
     :param: debug true if you want to see debug messages.
     
     :returns: Instance of MRZ
     */
    @objc public override init(scan: String, debug: Bool = false) {
        super.init(scan: scan, debug: debug)
        _debug = debug
        print("PROCESANDO UN MRZ TD1")
        var lines: [String] = scan.characters.split(separator: "\n").map({String($0)})
        
        if(lines.count >= 4){
            //probabily i'm capturing also the barcode on top to the MRZ
            //let's try skippong the first line
            
            let tmp = lines.suffix(3)
            lines = Array(tmp);
        }
        
        var longLines: [String] = []
        for line in lines {
            let cleaned = line.replace(target: " ", with: "")
            if cleaned.characters.count > 30 {
                return
            }
            longLines.append(line)
        }
        
        
        if longLines.count < 3 { return }
        if longLines.count > 3 { return }
        
        let line1: String = MRZTD1.cleanup(line: longLines[0])
        let line2: String = MRZTD1.cleanup(line: longLines[1])
        let line3: String = MRZTD1.cleanup(line: longLines[2])
        
        if(line1.count + line2.count + line3.count == 90){
            process(l1: line1,
                    l2: line2,
                    l3: line3)
            
        }
    }
    
    @objc override func isValid() -> Float {
        return _isValid
        
    }
    
    /**
     Do you want to see the progress in the log
     
     :param: line The data that will be logged
     */
    fileprivate func debugLog(_ line: String) {
        if _debug {
            print(line)
        }
    }
    
    /**
     Process the 3 MRZ lines
     
     :param: l1 First line
     :param: l2 Second line
     :param: l3 Third line
     
     */
    fileprivate func process(l1: String, l2: String, l3: String) {
        
        let line1: String = l1
        let line2: String = l2
        let line3: String = l3
        
        print("PROCESANDO UN MRZ TD1")
        debugLog("Processing line 1 : \(line1)")
        debugLog("Processing line 2 : \(line2)")
        debugLog("Processing line 3 : \(line3)")
        
        // Line 1 parsing
        documentType = line1.subString(0, to: 0)
        //Italian Case
        if documentType == "C" {
            documentType = "I"
        }
        debugLog("Document type : \(documentType)")
        documentSubType = line1.subString(1, to: 1)
        if documentSubType == "<" || documentSubType == "O" || documentSubType == "0"{
            documentSubType = "ID"
        }
        countryCode = line1.subString(2, to: 4).replace(target: "<", with: " ")
        if countryCode == "D  " || countryCode == "0  " {
            countryCode = "DEU"
        }
        debugLog("Country code : \(countryCode)")
        countryCode = countryCode.replace(target: "5", with: "S")
        countryCode = countryCode.replace(target: "1", with: "I")
        countryCode = countryCode.replace(target: "3", with: "E")
        countryCode = countryCode.replace(target: "0", with: "O")
        countryCode = countryCode.replace(target: "2", with: "Z")
        countryCode = countryCode.replace(target: "8", with: "B")
        if countryCode == "ESP" {
            passportNumber = line1.subString(15, to: 23)
            debugLog("IDNumber : \(passportNumber)")
        } else {
            passportNumber = line1.subString(5, to: 13)
            debugLog("IDNumber : \(passportNumber)")
        }
        let passportNumberCheck = line1.subString(14, to: 14).toNumber()
        
        let birth = line2.subString(0, to: 5).toNumber()
        let birthValidation = line2.subString(6, to: 6).toNumber()
        dateOfBirth = MRZTD1.birthDateFromString(birth)
        debugLog("date of birth : \(dateOfBirth)")
        
        sex = line2.subString(7, to: 7)
        debugLog("sex : \(sex)")
        
        let expiration = line2.subString(8, to: 13).toNumber()
        expirationDate = MRZTD1.expirationDateFromString(expiration)
        debugLog("date of expiration : \(expirationDate)")
        let expirationValidation = line2.subString(14, to: 14).toNumber()
        
        nationality = line2.subString(15, to: 17).replace(target: "<", with: " ")
        if nationality == "D  " || nationality == "0  " {
            nationality = "DEU"
        }
        nationality = nationality.replace(target: "5", with: "S")
        nationality = nationality.replace(target: "1", with: "I")
        nationality = nationality.replace(target: "3", with: "E")
        nationality = nationality.replace(target: "0", with: "O")
        nationality = nationality.replace(target: "2", with: "Z")
        nationality = nationality.replace(target: "8", with: "B")
        debugLog("nationality : \(nationality)")
        
        let data_line1 = line1.subString(5, to: 29)
        let data_line2_a = line2.subString(0, to: 6)
        let data_line2_b = line2.subString(8, to: 14)
        let data_line2_c = line2.subString(18, to: 28)
        
        let data = "\(data_line1)\(data_line2_a)\(data_line2_b)\(data_line2_c)"
        let dataValidation = line2.subString(29, to: 29).toNumber()
        
        // Line 3 parsing
        var nameArray = line3.components(separatedBy: "<<")
        lastName = nameArray[0].replace(target: "<", with: " ")
        lastName = lastName.replace(target: "5", with: "S")
        lastName = lastName.replace(target: "1", with: "I")
        lastName = lastName.replace(target: "3", with: "E")
        lastName = lastName.replace(target: "0", with: "O")
        lastName = lastName.replace(target: "2", with: "Z")
        lastName = lastName.replace(target: "8", with: "B")
        debugLog("Last name : \(lastName)")
        firstName = nameArray.count > 1 ? nameArray[1].replace(target: "<", with: " ") : ""
        firstName = firstName.replace(target: "5", with: "S")
        firstName = firstName.replace(target: "1", with: "I")
        firstName = firstName.replace(target: "3", with: "E")
        firstName = firstName.replace(target: "0", with: "O")
        firstName = firstName.replace(target: "2", with: "Z")
        firstName = firstName.replace(target: "8", with: "B")
        debugLog("First name : \(firstName)")
        
        validation(passportN: passportNumber, passportNC: passportNumberCheck, birth: birth, birthC: birthValidation, expiration: expiration, expirationC: expirationValidation, data: data, dataC: dataValidation)
        
        
        
        // Final cleaning up
        documentSubType = documentSubType.replace(target: "<", with: "")
        passportNumber = passportNumber.replace(target: "<", with: "")
        
    }
    
    func validation(passportN: String, passportNC: String, birth: String, birthC: String, expiration: String, expirationC: String, data: String, dataC: String){
        // Validation
        
        _isValid = 1
        
        if countryCode != "ESP" && countryCode != "BEL" && countryCode != "PRT"{
            passportNumberIsValid = MRZTD1.validate(passportN, check: passportNC)
            if !passportNumberIsValid {
                print("--> IDNumber is invalid")
            }
            _isValid = _isValid * (passportNumberIsValid ? 1 : 0.9)
        }
        
        dateOfBirthIsValid = MRZTD1.validate(birth, check: birthC)
        if !dateOfBirthIsValid {
            print("--> DateOfBirth is invalid")
        }
        _isValid = _isValid * (dateOfBirthIsValid ? 1 : 0.9)
        
        _isValid = _isValid * (MRZTD1.validate(expiration, check: expirationC) ? 1 : 0.9)
        
        
        dataIsValid = MRZTD1.validate(data, check: dataC)
        if !dataIsValid {
            print("--> Date is invalid")
        }
        _isValid = _isValid * (dataIsValid ? 1 : 0.9)
        
    }
    
    /**
     Cleanup a line of text
     
     :param: line The line that needs to be cleaned up
     :returns: Returns the cleaned up text
     */
    fileprivate class func cleanup(line: String) -> String {
        var t = line.components(separatedBy: " ")
        if t.count > 1 {
            // are there extra characters added
            for p in t {
                if p.characters.count == 30 {
                    return p
                }
            }
            // was there one or more extra space added
            if "\(t[0])\(t[1])".characters.count == 30 {
                return "\(t[0])\(t[1])"
            } else if  "\(t[t.count-2])\(t[t.count-1])".characters.count == 30 {
                return "\(t[t.count-2])\(t[t.count-1])"
            } else {
                return line.replace(target: " ", with: "")
            }
        }
        return line // assume the garbage characters are at the end
    }
    
}

extension String
{
    func replace(target: String, withString: String) -> String
    {
        return self.replacingOccurrences(of: target, with: withString, options: NSString.CompareOptions.literal, range: nil)
    }
}
