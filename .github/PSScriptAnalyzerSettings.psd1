@{
    # These are standalone scripts, not a published module. The rules below
    # target module-authoring conventions (verb/noun naming, ShouldProcess,
    # console output) that don't apply here, so they're excluded. Correctness
    # and bug-catching rules stay on.
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                      # installer prints to the console on purpose
        'PSUseApprovedVerbs',                         # private helpers (Make-Bar, To-Epoch, Fmt-Dur…)
        'PSUseSingularNouns',                         # private helpers (Compute-Langs)
        'PSUseShouldProcessForStateChangingFunctions', # Reset-Label is a pure formatter, not stateful
        'PSAvoidUsingPositionalParameters',            # terse helpers (Seg, Get-P) use positional args by design
        'PSAvoidUsingEmptyCatchBlock',                 # a status line must never throw — it degrades silently
        'PSPossibleIncorrectUsageOfRedirectionOperator', # false positive on intentional `2>$null` stderr redirects
        'PSUseBOMForUnicodeEncodedFile'                # BOM-less UTF-8 is intentional; script sets OutputEncoding itself
    )
}
