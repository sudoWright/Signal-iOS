//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalServiceKit

public struct RegistrationCountryState: Equatable, Dependencies {
    // e.g. France
    public let countryName: String
    // e.g. +33
    public let callingCode: String
    // e.g. FR
    public let countryCode: String

    public init(countryName: String,
                callingCode: String,
                countryCode: String) {
        self.countryName = countryName
        self.callingCode = callingCode
        self.countryCode = countryCode
    }

    public static var defaultValue: RegistrationCountryState {
        AssertIsOnMainThread()

        var countryCode: String = PhoneNumber.defaultCountryCode()
        if
            let lastRegisteredCountryCode = RegistrationValues.lastRegisteredCountryCode(),
            !lastRegisteredCountryCode.isEmpty
        {
            countryCode = lastRegisteredCountryCode
        }

        let callingCodeNumber: NSNumber = phoneNumberUtil.getCountryCode(forRegion: countryCode)
        let callingCode = "\(COUNTRY_CODE_PREFIX)\(callingCodeNumber)"
        let countryName = PhoneNumberUtil.countryName(fromCountryCode: countryCode)

        return RegistrationCountryState(countryName: countryName, callingCode: callingCode, countryCode: countryCode)
    }

    // MARK: -

    public static func countryState(forE164 e164: String) -> RegistrationCountryState? {
        for countryState in allCountryStates {
            if e164.hasPrefix(countryState.callingCode) {
                return countryState
            }
        }
        return nil
    }

    public static var allCountryStates: [RegistrationCountryState] {
        RegistrationCountryState.buildCountryStates(searchText: nil)
    }

    public static func buildCountryStates(searchText: String?) -> [RegistrationCountryState] {
        let searchText = searchText?.strippedOrNil
        let countryCodes: [String] = NSObject.phoneNumberUtil.countryCodes(forSearchTerm: searchText)
        return RegistrationCountryState.buildCountryStates(countryCodes: countryCodes)
    }

    public static func buildCountryStates(countryCodes: [String]) -> [RegistrationCountryState] {
        return countryCodes.compactMap { (countryCode: String) -> RegistrationCountryState? in
            guard let countryCode = countryCode.strippedOrNil else {
                owsFailDebug("Invalid countryCode.")
                return nil
            }
            guard let callingCode = NSObject.phoneNumberUtil.callingCode(fromCountryCode: countryCode)?.strippedOrNil else {
                owsFailDebug("Invalid callingCode.")
                return nil
            }
            guard let countryName = PhoneNumberUtil.countryName(fromCountryCode: countryCode).strippedOrNil else {
                owsFailDebug("Invalid countryName.")
                return nil
            }
            guard callingCode != "+0" else {
                owsFailDebug("Invalid callingCode.")
                return nil
            }

            return RegistrationCountryState(countryName: countryName,
                                          callingCode: callingCode,
                                          countryCode: countryCode)
        }
    }
}

// MARK: -

public struct RegistrationPhoneNumber {
    public let countryState: RegistrationCountryState
    public let nationalNumber: String
    public let e164: E164?

    public init(countryState: RegistrationCountryState, nationalNumber: String) {
        self.countryState = countryState
        self.nationalNumber = nationalNumber
        self.e164 = E164("\(countryState.callingCode)\(nationalNumber)")
    }

    public init?(e164: E164) {
        guard
            let countryState = RegistrationCountryState.countryState(forE164: e164.stringValue),
            let nationalNumber = PhoneNumber(fromE164: e164.stringValue)?.nationalNumber
        else {
            return nil
        }
        self.countryState = countryState
        self.nationalNumber = nationalNumber
        self.e164 = e164
    }
}

// MARK: -

public class RegistrationValues: NSObject {

    private static let kKeychainService_LastRegistered = "kKeychainService_LastRegistered"
    private static let kKeychainKey_LastRegisteredCountryCode = "kKeychainKey_LastRegisteredCountryCode"
    private static let kKeychainKey_LastRegisteredPhoneNumber = "kKeychainKey_LastRegisteredPhoneNumber"

    private class func debugValue(forKey key: String) -> String? {
        AssertIsOnMainThread()

        guard OWSIsDebugBuild() else {
            return nil
        }

        do {
            let value = try CurrentAppContext().keychainStorage().string(forService: kKeychainService_LastRegistered, key: key)
            return value
        } catch {
            // The value may not be present in the keychain.
            return nil
        }
    }

    private class func setDebugValue(_ value: String, forKey key: String) {
        AssertIsOnMainThread()

        guard OWSIsDebugBuild() else {
            return
        }

        do {
            try CurrentAppContext().keychainStorage().set(string: value, service: kKeychainService_LastRegistered, key: key)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    public class func lastRegisteredCountryCode() -> String? {
        return debugValue(forKey: kKeychainKey_LastRegisteredCountryCode)
    }

    public class func setLastRegisteredCountryCode(value: String) {
        setDebugValue(value, forKey: kKeychainKey_LastRegisteredCountryCode)
    }

    public class func lastRegisteredPhoneNumber() -> String? {
        return debugValue(forKey: kKeychainKey_LastRegisteredPhoneNumber)
    }

    public class func setLastRegisteredPhoneNumber(value: String) {
        setDebugValue(value, forKey: kKeychainKey_LastRegisteredPhoneNumber)
    }
}
