[#var NFA_RANGE_THRESHOLD = 16]
[#var multipleLexicalStates = grammar.lexerData.lexicalStates.size()>1]
[#--
  Generate all the NFA transition code
  for the given lexical state
--]
[#macro GenerateStateCode lexicalState]
  [#list lexicalState.canonicalSets as state]
     [@NFA.GenerateNfaMethod state/]
  [/#list]

  [#list lexicalState.allNfaStates as state]
    [#if state.moveRanges.size() >= NFA_RANGE_THRESHOLD]
      [@NFA.GenerateMoveArray state/]
    [/#if]
  [/#list]

  static private void NFA_FUNCTIONS_init() {
    [#if multipleLexicalStates]
      NfaFunction[] functions = new NfaFunction[]
    [#else]
      nfaFunctions = new NfaFunction[]
    [/#if] 
    {
    [#list lexicalState.canonicalSets as state]
      ${lexicalState.name}::${state.methodName}
      [#if state_has_next],[/#if]
    [/#list]
    };
    [#if multipleLexicalStates]
      functionTableMap.put(LexicalState.${lexicalState.name}, functions);
    [/#if]
  }
[/#macro]

[#--
   Generate the array representing the characters
   that this NfaState "accepts".
   This corresponds to the moveRanges field in 
   org.congocc.core.NfaState
--]
[#macro GenerateMoveArray nfaState]
  [#var moveRanges = nfaState.moveRanges]
  [#var arrayName = nfaState.movesArrayName]
    static private int[] ${arrayName} = ${arrayName}_init();

    static private int[] ${arrayName}_init() {
        return new int[]
        {
        [#list nfaState.moveRanges as char]
          ${globals.displayChar(char)}
          [#if char_has_next],[/#if]
        [/#list]
        };
    }
[/#macro] 

[#--
   Generate the method that represents the transitions
   that correspond to an instanceof org.congocc.core.CompositeStateSet
--]
[#macro GenerateNfaMethod nfaState]  
    static private TokenType ${nfaState.methodName}(int ch, BitSet nextStates, EnumSet<TokenType> validTypes) {
      TokenType type = null;
    [#var states = nfaState.orderedStates, lastBlockStartIndex=0]
    [#list states as state]
      [#if state_index ==0 || !state.moveRanges.equals(states[state_index-1].moveRanges)]
          [#-- In this case we need a new if or possibly else if --]
         [#if state_index == 0 || state.overlaps(states.subList(lastBlockStartIndex, state_index))]
           [#-- If there is overlap between this state and any of the states
                 handled since the last lone if, we start a new if-else 
                 If not, we continue in the same if-else block as before. --]
           [#set lastBlockStartIndex = state_index]
               if
         [#else]
               else if
         [/#if]    
           ([@NFA.NfaStateCondition state /]) {
      [/#if]
      [#if state.nextStateIndex >= 0]
         nextStates.set(${state.nextStateIndex});
      [/#if]
      [#if !state_has_next || !state.moveRanges.equals(states[state_index+1].moveRanges)]
        [#-- We've reached the end of the block. --]
          [#var type = state.nextStateType]
          [#if type??]
            if (validTypes == null || validTypes.contains(${type.label}))
              type = ${type.label};
          [/#if]
        }
      [/#if]
    [/#list]
      return type;
    }
[/#macro]

[#--
Generate the condition part of the NFA state transition
If the size of the moveRanges vector is greater than NFA_RANGE_THRESHOLD
it uses the canned binary search routine. For the smaller moveRanges
it just generates the inline conditional expression
--]
[#macro NfaStateCondition nfaState]
    [#if nfaState.moveRanges?size < NFA_RANGE_THRESHOLD]
      [@RangesCondition nfaState.moveRanges /]
    [#elseif nfaState.hasAsciiMoves && nfaState.hasNonAsciiMoves]
      ([@RangesCondition nfaState.asciiMoveRanges/])
      || (ch >=128 && checkIntervals(${nfaState.movesArrayName}, ch))
    [#else]
      checkIntervals(${nfaState.movesArrayName}, ch)
    [/#if]
[/#macro]

[#-- 
This is a recursive macro that generates the code corresponding
to the accepting condition for an NFA state. It is used
if NFA state's moveRanges array is smaller than NFA_RANGE_THRESHOLD
(which is set to 16 for now)
--]
[#macro RangesCondition moveRanges]
    [#var left = moveRanges[0], right = moveRanges[1]]
    [#var displayLeft = globals.displayChar(left), displayRight = globals.displayChar(right)]
    [#var singleChar = left == right]
    [#if moveRanges?size==2]
       [#if singleChar]
          ch == ${displayLeft}
       [#elseif left +1 == right]
          ch == ${displayLeft} || ch == ${displayRight}
       [#else]
          ch >= ${displayLeft} 
          [#if right < 1114111]
             && ch <= ${displayRight}
          [/#if]
       [/#if]
    [#else]
       ([@RangesCondition moveRanges[0..1]/])||([@RangesCondition moveRanges[2..moveRanges?size-1]/])
    [/#if]
[/#macro]

