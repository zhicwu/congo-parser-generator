[#-- A place to put some utility routines used in various templates. Currently doesn't
     really have much! --]

[#var TT = "TokenType."]

[#macro enumSet varName tokenNames indent=0]
[#var is = ""?right_pad(indent)]
[#var size = tokenNames?size]
[#if size = 0]
${is}private static readonly HashSet<TokenType> ${varName} = Utils.GetOrMakeSet();
[#else]
${is}private static readonly HashSet<TokenType> ${varName} = Utils.GetOrMakeSet(
[#list tokenNames as type]
${is}    TokenType.${type}[#if type_has_next],[/#if]
[/#list]
${is});
[/#if]

[/#macro]

[#macro firstSetVar expansion]
    [@enumSet expansion.firstSetVarName expansion.firstSet.tokenNames 8 /]
[/#macro]

[#macro finalSetVar expansion]
    [@enumSet expansion.finalSetVarName expansion.finalSet.tokenNames 8 /]
[/#macro]

[#macro followSetVar expansion]
    [@enumSet expansion.followSetVarName expansion.followSet.tokenNames 8 /]
[/#macro]


[#var newVarIndex=0]
[#-- Just to generate a new unique variable name
  All it does is tack an integer (that is incremented)
  onto the type name, and optionally initializes it to some value--]
[#macro newVar type init=null]
   [#set newVarIndex = newVarIndex+1]
   ${type} ${type?lower_case}${newVarIndex}
   [#if init??]
      = ${init}
   [/#if]
   ;
[/#macro]

[#macro newVarName prefix]
${prefix}${newID()}[#rt]
[/#macro]

[#function newID]
    [#set newVarIndex = newVarIndex+1]
    [#return newVarIndex]
[/#function]

[#-- A macro to use at one's convenience to comment out a block of code --]
[#macro comment]
[#var content, lines]
[#set content][#nested/][/#set]
[#set lines = content?split("\n")]
[#list lines as line]
// ${line}
[/#list]
[/#macro]

[#function bool val]
[#return val?string("true", "false")/]
[/#function]

[#macro HandleLexicalStateChange expansion inLookahead indent]
[#var is=""?right_pad(indent)]
[#-- ${is}# DBG > HandleLexicalStateChange ${indent} ${expansion.simpleName} --]
[#var resetToken = inLookahead?string("currentLookaheadToken", "LastConsumedToken")]
[#if expansion.specifiedLexicalState??]
  [#var prevLexicalStateVar = newVarName("previousLexicalState")]
${is}LexicalState ${prevLexicalStateVar} = tokenSource.LexicalState;
${is}tokenSource.Reset(${resetToken}, LexicalState.${expansion.specifiedLexicalState});
${is}try {
[#nested indent + 8 /]
${is}}
${is}finally {
${is}    if (${prevLexicalStateVar} != LexicalState.${expansion.specifiedLexicalState}) {
${is}        if (${resetToken}.Next != null) {
${is}            tokenSource.Reset(${resetToken}, ${prevLexicalStateVar});
${is}        }
${is}        else {
${is}            tokenSource.SwitchTo(${prevLexicalStateVar});
${is}        }
${is}        _nextTokenType = null;
${is}    }
${is}}
[#elseif expansion.tokenActivation??]
  [#var tokenActivation = expansion.tokenActivation]
  [#var prevActives = newVarName("previousActives")]
  [#var somethingChanged = newVarName("somethingChanged")]
${is}var ${prevActives} = new HashSet<TokenType>(tokenSource.ActiveTokenTypes);
${is}var ${somethingChanged} = false;
[#if tokenActivation.activatedTokens?size > 0]
${is}${somethingChanged} = ActivateTokenTypes(
  [#list tokenActivation.activatedTokens as tokenName]
${is}    ${TT}${tokenName}[#if tokenName_has_next],[/#if]
  [/#list]
${is});
[/#if]
[#if tokenActivation.deactivatedTokens?size > 0]
${is}${somethingChanged} = ${somethingChanged} || DeactivateTokenTypes(
  [#list tokenActivation.deactivatedTokens as tokenName]
${is}    ${TT}${tokenName}[#if tokenName_has_next],[/#if]
  [/#list]
${is});
[/#if]
${is}try {
  [#nested indent + 4 /]
${is}}
${is}finally {
${is}    tokenSource.ActiveTokenTypes = ${prevActives};
${is}    if (${somethingChanged}) {
${is}        tokenSource.Reset(GetToken(0));
${is}        _nextTokenType = null;
${is}    }
${is}}
[#else]
  [#nested indent /]
[/#if]
[#-- ${is}# DBG < HandleLexicalStateChange ${indent} ${expansion.simpleName} --]
[/#macro]

