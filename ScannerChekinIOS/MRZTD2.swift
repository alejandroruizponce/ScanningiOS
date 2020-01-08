//
//  MRZTD2.swift
//  EVGPUImage2
//
//  Created by Alejandro Ruiz Ponce on 20/11/2018.
//

import Foundation


@objc(MRZTD2)
open class MRZTD2: MRZParser {
    // check data with http://en.wikipedia.org/wiki/Machine-readable_passport
    
    /// Was the last scan valid. A value of 1 is for when all validations are OK
    private var _isValid: Float = 0
    
    /// Do you want to see debug messages? Set to true (see init) to see what's going on.
    private var _debug = false
    
    /// The document type from the 1st line of the MRZ. (start 1, len 1)
    @objc public var documentType: String = ""
    /// The document sub type from the 1st line of the MRZ. (start 2, len 1)
    @objc public var documentSubType: String = ""
    /// The country code from the 1st line of the MRZ (start 3, len 3)
    @objc public var countryCode: String = ""
    /// The last name from the 1st line of the MRZ (start 6, len 39, until first <<)
    @objc public var lastName: String = ""
    /// The firstname from the 1st line of the MRZ (start 6, len 39, after first <<)
    @objc public var firstName: String = ""
    
    /// The passport number from the 2nd line of the MRZ. (start 1, len 9)
    @objc public var passportNumber: String = ""
    /// start 10, len 1 - validating the passportNumber
    private var passportNumberIsValid = false
    /// The nationality from the 2nd line of the MRZ. (start 11, len 3)
    @objc public var nationality: String = ""
    /// The date of birth from the 2nd line of the MRZ (start 14, len 6)
    @objc public var dateOfBirth: Date?
    /// start 20, len 1 - validating the dateOfBirth
    private var dateOfBirthIsValid = false
    /// The sex from the 2nd line of the MRZ. (start 21, len 1)
    @objc public var sex: String = ""
    /// The expiration date from the 2nd line of the MRZ. (start 22, len 6)
    @objc public var expirationDate: Date?
    /// start 28, len 1 - validating the expirationDate
    private var expirationDateIsValid = false
    /// The personal number from the 2nd line of the MRZ. (start 29, len 14
    @objc public var personalNumber: String = ""
    /// start 43, len 1 - validating the personalNumber
    private var personalNumberIsValid = false
    // start 44, len 1 - validating passport number, date of birth, expiration date
    private var dataIsValid = false
    
    
    /**
     Convenience method for getting all data in a dictionary
     
     :returns: Return all fields in a dictionary
     */
    @objc public override func data() -> Dictionary<String, Any> {
        return ["documentType"    : documentType,
                "documentSubType" : documentSubType,
                "countryCode"     : countryCode,
                "lastName"        : lastName,
                "firstName"       : firstName,
                "IDNumber"  : passportNumber,
                "nationality"     : nationality,
                "dateOfBirth"     : MRZTD2.stringFromDate(dateOfBirth),
                "sex"             : sex,
                "expirationDate"  : MRZTD2.stringFromDate(expirationDate),
                "personalNumber"  : personalNumber]
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
        print("-------------PROCESANDO MRZ TD2 -------------")
        let lines: [String] = scan.characters.split(separator: "\n").map({String($0)})
        var longLines: [String] = []
        for line in lines {
            let cleaned = line.replace(target: " ", with: "")
            if cleaned.characters.count > 35 {
                longLines.append(line)
            }
        }
        if longLines.count < 2 { return }
        if longLines.count == 2 {
            process(l1: longLines[0].replace(target: " ", with: ""),
                    l2: longLines[1].replace(target: " ", with: ""))
        } else if longLines.last?.components(separatedBy: "<").count ?? 0 > 1 {
            process(l1: longLines[longLines.count-2],
                    l2: longLines[longLines.count-1])
        } else {
            process(l1: longLines[longLines.count-3].replace(target: " ", with: ""),
                    l2: longLines[longLines.count-2].replace(target: " ", with: ""))
        }
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
    
    @objc override func isValid() -> Float {return _isValid}
    
    
    /**
     Process the 2 MRZ lines
     
     :param: l1 First line
     :param: l2 Second line
     */
    fileprivate func process(l1: String, l2: String) {
        
        let line1 = MRZTD2.cleanup(line: l1)
        let line2 = MRZTD2.cleanup(line: l2)
        
        
        debugLog("Processing line 1 : \(line1)")
        debugLog("Processing line 2 : \(line2)")
        
        // Line 1 parsing
        documentType = line1.subString(0, to: 0)
        debugLog("Document type : \(documentType)")
        documentSubType = line1.subString(1, to: 1)
        if (documentType != "P" && documentSubType != "P") {
            countryCode = line1.subString(2, to: 4).replace(target: "<", with: " ")
            debugLog("Country code : \(countryCode)")
            
            if countryCode == "FRA"{
                print("-------------PROCESANDO MRZ TD2 FRANCES -------------")
                firstName = line1.subString(5, to: 29).replace(target: "<", with: "")
                debugLog("First name : \(firstName)")
                passportNumber = line2.subString(0, to: 11)
                debugLog("IDNumber : \(passportNumber)")
                let passportNumberCheck = line2.subString(12, to: 12).toNumber()
                nationality = "FRA"
                lastName = line2.subString(13, to: 26).replace(target: "<", with: " ")
                debugLog("Last name : \(lastName)")
                let birth = line2.subString(27, to: 32).toNumber()
                dateOfBirth = MRZTD2.birthDateFromString(birth)
                debugLog("date of birth : \(dateOfBirth)")
                let birthValidation = line2.subString(33, to: 33).toNumber()
                sex = line2.subString(34, to: 34)
                debugLog("sex : \(sex)")
                let expiration = ""
                let dataValidation = line2.subString(35, to: 35).toNumber()
                let data_line2_a = line2.subString(0, to: 12)
                let data_line2_b = line2.subString(27, to: 33)
                let data = "\(data_line2_a)\(data_line2_b)"
                
                _isValid = 1
                
                passportNumberIsValid = MRZTD3.validate(passportNumber, check: passportNumberCheck)
                if !passportNumberIsValid {
                    print("--> IDNumber is invalid")
                }
                _isValid = _isValid * (passportNumberIsValid ? 1 : 0.9)
                
                dateOfBirthIsValid = MRZTD3.validate(birth, check: birthValidation)
                if !dateOfBirthIsValid {
                    print("--> DateOfBirth is invalid")
                }
                _isValid = _isValid * (dateOfBirthIsValid ? 1 : 0.9)
                
                /*
                 dataIsValid = MRZTD3.validate(data, check: dataValidation)
                 if !dataIsValid {
                 print("--> Data is invalid")
                 }
                 _isValid = _isValid * (dataIsValid ? 1 : 0.9)*/
                
                
            } else  {
                print("PROCESANDO TD2 NO FRANCES")
                var nameArray = line1.components(separatedBy: "<<")
                firstName = nameArray[0].replace(target: "ID\(countryCode)", with: " ")
                debugLog("First name : \(firstName)")
                
                lastName = nameArray.count > 1 ? nameArray[1].replace(target: "<", with: " ") : ""
                debugLog("Last name : \(lastName)")
                
                if countryCode == "ROU" {
                    passportNumber = line2.subString(0, to: 7)
                    debugLog("IDNumber : \(passportNumber)")
                } else {
                    passportNumber = line2.subString(0, to: 8)
                    debugLog("IDNumber : \(passportNumber)")
                }
                let passportNumberCheck = line2.subString(9, to: 9).toNumber()
                
                nationality = line2.subString(10, to: 12).replace(target: "<", with: " ")
                debugLog("Nationality : \(passportNumber)")
                
                let birth = line2.subString(13, to: 18).toNumber()
                dateOfBirth = MRZTD2.birthDateFromString(birth)
                debugLog("date of birth : \(dateOfBirth)")
                let birthValidation = line2.subString(19, to: 19).toNumber()
                
                sex = line2.subString(20, to: 20)
                debugLog("sex : \(sex)")
                
                let expiration = line2.subString(21, to: 26).toNumber()
                expirationDate = MRZTD1.expirationDateFromString(expiration)
                debugLog("date of expiration : \(expirationDate)")
                let expirationValidation = line2.subString(27, to: 27).toNumber()
                
                let dataValidation = line2.subString(35, to: 35).toNumber()
                
                let data_line2_a = line2.subString(0, to: 9)
                let data_line2_b = line2.subString(10, to: 19)
                let data_line2_c = line2.subString(20, to: 27)
                let data = "\(data_line2_a)\(data_line2_b)\(data_line2_c)"
                
                _isValid = 1
                
                if countryCode != "ROU"{
                    passportNumberIsValid = MRZTD3.validate(passportNumber, check: passportNumberCheck)
                    if !passportNumberIsValid {
                        print("--> IDNumber is invalid")
                    }
                    _isValid = _isValid * (passportNumberIsValid ? 1 : 0.9)
                    
                    dateOfBirthIsValid = MRZTD3.validate(birth, check: birthValidation)
                    if !dateOfBirthIsValid {
                        print("--> DateOfBirth is invalid")
                    }
                    _isValid = _isValid * (dateOfBirthIsValid ? 1 : 0.9)
                    
                    dataIsValid = MRZTD3.validate(data, check: dataValidation)
                    if !dataIsValid {
                        print("--> Date is invalid")
                    }
                    _isValid = _isValid * (dataIsValid ? 1 : 0.9)
                }
            }
        }
        
        // Final cleaning up
        documentSubType = documentSubType.replace(target: "<", with: "")
        personalNumber = personalNumber.replace(target: "<", with: "")
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
                if p.characters.count == 36 {
                    return p
                }
            }
            // was there one or more extra space added
            if "\(t[0])\(t[1])".characters.count == 36 {
                return "\(t[0])\(t[1])"
            } else if  "\(t[t.count-2])\(t[t.count-1])".characters.count == 36 {
                return "\(t[t.count-2])\(t[t.count-1])"
            } else {
                return line.replace(target: " ", with: "")
            }
        }
        return line // assume the garbage characters are at the end
    }
    
}

