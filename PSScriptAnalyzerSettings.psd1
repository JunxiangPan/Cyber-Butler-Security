@{
    # Correctness/security rules retained for the release gate.
    Severity = @('Error', 'Warning')
    # Style/naming rules are explicitly excluded here, with reasons, instead
    # of being hidden by a blanket suppression in the audit script.
    # PSUseSingularNouns: command names in this legacy codebase are already
    #   consumed by scheduled tasks; renaming would break callers.
    # PSUseShouldProcessForStateChangingFunctions: installer functions are
    #   guarded by the installer approval tokens, not by -WhatIf.
    # PSAvoidGlobalVars / PSReviewUnusedParameter / PSAvoidUsingEmptyCatchBlock
    #   are handled separately or covered above.
    ExcludeRules = @(
        'PSUseSingularNouns',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseApprovedVerbs',
        'PSAvoidGlobalVars',
        'PSReviewUnusedParameter',
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingComputerNameHardcoded',
        'PSUseBOMForUnicodeEncodedFile',
        'PSUseSupportsShouldProcess'
    )
}
