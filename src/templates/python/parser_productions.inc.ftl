[#-- This template contains the core logic for generating the various parser routines. --]

[#import "common_utils.inc.ftl" as CU]

[#var nodeNumbering = 0]
[#var NODE_USES_PARSER = settings.nodeUsesParser]
[#var NODE_PREFIX = grammar.nodePrefix]
[#var currentProduction]

[#macro Productions]
# ===================================================================
# Start of methods for BNF Productions
# This code is generated by the parser_productions.inc.ftl template.
# ===================================================================
[#list grammar.parserProductions as production]
  [@CU.firstSetVar production.expansion/]
  [#if !production.onlyForLookahead]
    [#set currentProduction = production]
    [@ParserProduction production/]
  [/#if]
[/#list]
[#if settings.faultTolerant]
    [@BuildRecoverRoutines /]
[/#if]
[/#macro]

[#macro ParserProduction production]
[#if production.leadingComments?has_content]
    # ${production.leadingComments}
[/#if]
    # ${production.location}
    ${globals.startProduction()}def parse_${production.name}(self[#if production.parameterList?has_content], ${globals.translateParameters(production.parameterList)}[/#if]):
        # import pdb; pdb.set_trace()
        prev_production = self.currently_parsed_production
        self.currently_parsed_production = '${production.name}'
     [#--${production.javaCode!}
       This is actually inserted further down because
       we want the prologue java code block to be able to refer to
       CURRENT_NODE.
     --]
${BuildCode(production.expansion, 8)}
        self.currently_parsed_production = prev_production
    # end of parse_${production.name}${globals.endProduction()}

[/#macro]

[#macro BuildCode expansion indent]
[#var is=""?right_pad(indent)]
[#-- ${is}# DBG > BuildCode ${indent} ${expansion.simpleName} --]
   [#if expansion.simpleName != "ExpansionSequence" && expansion.simpleName != "ExpansionWithParentheses"]
${is}# Code for ${expansion.simpleName} specified at ${expansion.location}
  [/#if]
     [@CU.HandleLexicalStateChange expansion false indent; indent]
      [#if settings.faultTolerant && expansion.requiresRecoverMethod && !expansion.possiblyEmpty]
${is}if self.pending_recovery:
${is}    if self.debug_fault_tolerant:
${is}        logger.info('Re-synching to expansion at: ${expansion.location?j_string}')
${is}    self.${expansion.recoverMethodName}()
      [/#if]
       [@TreeBuildingAndRecovery expansion indent/]
     [/@CU.HandleLexicalStateChange]
[#-- ${is}# DBG < BuildCode ${indent} ${expansion.simpleName} --]
[/#macro]

[#macro TreeBuildingAndRecovery expansion indent]
[#-- This macro handles both tree building AND recovery. It doesn't seem right.
     It should probably be two macros. Also, it is too darned big. --]
[#var is=""?right_pad(indent)]
[#-- ${is}# DBG > TreeBuildingAndRecovery ${indent} --]
    [#var nodeVarName,
          production,
          treeNodeBehavior,
          buildTreeNode=false,
          closeCondition = "True",
          javaCodePrologue = null,
          parseExceptionVar = CU.newVarName("parseException"),
          callStackSizeVar = CU.newVarName("callStackSize"),
          canRecover = settings.faultTolerant && expansion.tolerantParsing && expansion.simpleName != "Terminal"
    ]
    [#set treeNodeBehavior = expansion.treeNodeBehavior]
    [#if expansion.parent.simpleName = "BNFProduction"]
      [#set production = expansion.parent]
      [#set javaCodePrologue = production.javaCode]
    [/#if]
    [#if settings.treeBuildingEnabled]
      [#set buildTreeNode = (treeNodeBehavior?is_null && production?? && !settings.nodeDefaultVoid)
                        || (treeNodeBehavior?? && !treeNodeBehavior.neverInstantiated)]
    [/#if]
    [#if !buildTreeNode && !canRecover]
${globals.translateCodeBlock(javaCodePrologue, indent)}[#rt]
${BuildExpansionCode(expansion, indent)}[#t]
    [#else]
     [#if buildTreeNode]
     [#set nodeNumbering = nodeNumbering +1]
     [#set nodeVarName = currentProduction.name + nodeNumbering]
${globals.pushNodeVariableName(nodeVarName)!}
      [#if !treeNodeBehavior?? && !production?is_null]
         [#if settings.smartNodeCreation]
            [#set treeNodeBehavior = {"name" : production.name, "condition" : "1", "gtNode" : true, "void" :false, "initialShorthand" : " > "}]
         [#else]
            [#set treeNodeBehavior = {"name" : production.name, "condition" : null, "gtNode" : false, "void" : false}]
         [/#if]
      [/#if]
      [#if treeNodeBehavior.condition?has_content]
         [#set closeCondition = globals.translateString(treeNodeBehavior.condition)]
         [#if treeNodeBehavior.gtNode]
            [#set closeCondition = "self.node_arity" + treeNodeBehavior.initialShorthand + closeCondition]
         [/#if]
      [/#if]
      [@createNode treeNodeBehavior nodeVarName false indent /]
      [/#if]
         [#-- I put this here for the hypertechnical reason
              that I want the initial code block to be able to
              reference CURRENT_NODE. --]
${globals.translateCodeBlock(javaCodePrologue, indent)}
${is}${parseExceptionVar} = None
${is}${callStackSizeVar} = len(self.parsing_stack)
${is}try:
${is}    pass  # in case there's nothing else in the try clause!
[#-- ${is}    # nested code starts, passing indent of ${indent + 4} --]
${BuildExpansionCode(expansion, indent + 4)}[#t]
[#-- ${is}    # nested code ends --]
${is}except ParseException as e:
${is}    ${parseExceptionVar} = e
            [#if !canRecover]
              [#if settings.faultTolerant]
${is}    if self.is_tolerant: self.pending_recovery = True
              [/#if]
${is}    raise
            [#else]
${is}    if not self.is_tolerant: raise
${is}    self.pending_recovery = True
         ${expansion.customErrorRecoveryBlock!}
             [#if !production?is_null && production.returnType != "void"]
                [#var rt = production.returnType]
                [#-- We need a return statement here or the code won't compile! --]
                [#if rt = "int" || rt="char" || rt=="byte" || rt="short" || rt="long" || rt="float"|| rt="double"]
${is}       return 0
                [#else]
${is}       return None
                [/#if]
             [/#if]
          [/#if]
${is}finally:
${is}    self.restore_call_stack(${callStackSizeVar})
             [#if buildTreeNode]
${is}    if ${nodeVarName}:
${is}        if ${parseExceptionVar} is None:
${is}            self.close_node_scope(${nodeVarName}, ${closeCondition})
                     [#list grammar.closeNodeHooksByClass[nodeClassName(treeNodeBehavior)]! as hook]
${is}            ${hook}(${nodeVarName})
                     [/#list]
${is}        else:
                  [#if settings.faultTolerant]
${is}            self.close_node_scope(${nodeVarName}, True)
${is}            ${nodeVarName}.dirty = True
                  [#else]
${is}            self.clear_node_scope()
                  [/#if]
${globals.popNodeVariableName()!}
             [/#if]

    [/#if]
[#-- ${is}# DBG < TreeBuildingAndRecovery ${indent} --]
[/#macro]

[#--  Boilerplate code to create the node variable --]
[#macro createNode treeNodeBehavior nodeVarName isAbstractType indent]
[#var is=""?right_pad(indent)]
   [#var nodeName = nodeClassName(treeNodeBehavior)]
${is}${nodeVarName} = None
   [#if !isAbstractType]
${is}if self.build_tree:
${is}    ${nodeVarName} = ${nodeName}([#if settings.nodeUsesParser]self[#else]self.input_source[/#if])
${is}    self.open_node_scope(${nodeVarName})
  [/#if]
[/#macro]

[#function nodeClassName treeNodeBehavior]
   [#if treeNodeBehavior?? && treeNodeBehavior.nodeName??]
      [#return NODE_PREFIX + treeNodeBehavior.nodeName]
   [/#if]
   [#return NODE_PREFIX + currentProduction.name]
[/#function]


[#macro BuildExpansionCode expansion indent]
[#var is=""?right_pad(indent)]
[#var classname=expansion.simpleName]
[#-- ${is}# DBG > BuildExpansionCode ${indent} ${classname} --]
    [#var prevLexicalStateVar = CU.newVarName("previousLexicalState")]
    [#if classname = "ExpansionWithParentheses"]
${BuildExpansionCode(expansion.nestedExpansion, indent)}[#t]
    [#elseif classname = "CodeBlock"]
${globals.translateCodeBlock(expansion, indent)}
    [#elseif classname = "UncacheTokens"]
${is}self.uncache_tokens()
    [#elseif classname = "Failure"]
       [@BuildCodeFailure expansion indent /]
    [#elseif classname = "TokenTypeActivation"]
       [@BuildCodeTokenTypeActivation expansion indent /]
    [#elseif classname = "ExpansionSequence"]
       [@BuildCodeSequence expansion indent /]
    [#elseif classname = "NonTerminal"]
       [@BuildCodeNonTerminal expansion indent /]
    [#elseif classname = "Terminal"]
       [@BuildCodeTerminal expansion indent /]
    [#elseif classname = "TryBlock"]
       [@BuildCodeTryBlock expansion indent /]
    [#elseif classname = "AttemptBlock"]
       [@BuildCodeAttemptBlock expansion indent /]
    [#elseif classname = "ZeroOrOne"]
       [@BuildCodeZeroOrOne expansion indent /]
    [#elseif classname = "ZeroOrMore"]
       [@BuildCodeZeroOrMore expansion indent /]
    [#elseif classname = "OneOrMore"]
        [@BuildCodeOneOrMore expansion indent /]
    [#elseif classname = "ExpansionChoice"]
        [@BuildCodeChoice expansion indent /]
    [#elseif classname = "Assertion"]
        [@BuildAssertionCode expansion indent /]
    [/#if]
[#-- ${is}# DBG < BuildExpansionCode ${indent} ${classname} --]
[/#macro]

[#macro BuildCodeFailure fail indent]
[#var is = ""?right_pad(indent)]
[#-- ${is}# DBG > BuildCodeFailure ${indent} --]
    [#if fail.code?is_null]
      [#if fail.exp??]
${is}self.fail('Failure: %s' % "${fail.exp?j_string}")
      [#else]
${is}self.fail('Failure')
      [/#if]
    [#else]
${globals.translateCodeBlock(fail.code, indent)}
    [/#if]
[#-- ${is}# DBG < BuildCodeFailure ${indent} --]
[/#macro]

[#macro BuildCodeTokenTypeActivation activation indent]
[#var is = ""?right_pad(indent)]
[#-- ${is}# DBG > BuildCodeTokenTypeActivation ${indent} --]
[#if activation.deactivate]
${is}self.deactivate_token_types(
[#else]
${is}self.activate_token_types(
[/#if]
[#list activation.tokenNames as name]
${is}    ${name}[#if name_has_next],[/#if]
[/#list]
${is})
[#-- ${is}# DBG < BuildCodeTokenTypeActivation ${indent} --]
[/#macro]

[#macro BuildCodeSequence expansion indent]
[#var is = ""?right_pad(indent)]
[#-- ${is}# DBG > BuildCodeSequence ${indent} --]
  [#list expansion.units as subexp]
${BuildCode(subexp, indent)}
  [/#list]
[#-- ${is}# DBG < BuildCodeSequence ${indent} --]
[/#macro]

[#macro BuildCodeTerminal terminal indent]
[#var is = ""?right_pad(indent), regexp=terminal.regexp]
[#-- ${is}# DBG > BuildCodeRegexp ${indent} --]
  [#var LHS = ""]
  [#if terminal.lhs??][#set LHS = terminal.lhs + "="][/#if]
  [#if !settings.faultTolerant]
${is}${LHS}self.consume_token(${regexp.label})
  [#else]
    [#var tolerant = terminal.tolerantParsing?string("True", "False")]
    [#var followSetVarName = "self." + terminal.followSetVarName]
    [#if terminal.followSet.incomplete]
      [#set followSetVarName = "follow_set" + CU.newID()]
${is}${followSetVarName} = None
${is}if self.outer_follow_set is not None:
${is}    ${followSetVarName} = set(self.${terminal.followSetVarName}) | self.outer_follow_set
    [/#if]
${is}${LHS}self.consume_token(${regexp.label}, ${tolerant}, ${followSetVarName})
  [/#if]
  [#if !terminal.childName?is_null]
${is}if self.build_tree:
${is}    child = self.peek_node()
${is}    name = '${terminal.childName}'
    [#if terminal.multipleChildren]
${is}    ${globals.currentNodeVariableName}.add_to_named_child_list(name, child)
    [#else]
${is}    ${globals.currentNodeVariableName}.set_named_child(name, child)
    [/#if]
  [/#if]
[#-- ${is}# DBG < BuildCodeRegexp ${indent} --]
[/#macro]

[#macro BuildCodeTryBlock tryblock indent]
[#var is = ""?right_pad(indent)]
${is}# DBG > BuildCodeTryBlock ${indent}
${is}try:
${BuildCode(tryblock.nestedExpansion, indent + 4)}
   [#list tryblock.catchBlocks as catchBlock]
   # TODO verify indentation
${is}${catchBlock}
   [/#list]
   # TODO verify indentation
${is}${tryblock.finallyBlock!}
${is}# DBG < BuildCodeTryBlock ${indent}
[/#macro]


[#macro BuildCodeAttemptBlock attemptBlock indent]
[#var is = ""?right_pad(indent)]
${is}# DBG > BuildCodeAttemptBlock ${indent}
${is}try:
${is}    self.stash_parse_state()
${BuildCode(attemptBlock.nestedExpansion, indent + 4)}
${is}    self.pop_parse_state()
${is}except ParseException:
${is}    self.restore_stashed_parse_state()
${BuildCode(attemptBlock.recoveryExpansion, indent + 4)}
${is}# DBG < BuildCodeAttemptBlock ${indent}
[/#macro]

[#macro BuildCodeNonTerminal nonterminal indent]
[#var is = ""?right_pad(indent)]
[#-- ${is}# DBG > BuildCodeNonTerminal ${indent} ${nonterminal.production.name} --]
   [#var production = nonterminal.production]
${is}self.push_onto_call_stack('${nonterminal.containingProduction.name}', '${nonterminal.inputSource?j_string}', ${nonterminal.beginLine}, ${nonterminal.beginColumn})
[#if settings.faultTolerant]
  [#var followSet = nonterminal.followSet]
  [#if !followSet.incomplete]
    [#if !nonterminal.beforeLexicalStateSwitch]
${is}self.outer_follow_set = self.${nonterminal.followSetVarName}
    [#else]
${is}self.outer_follow_set = None
    [/#if]
  [#elseif !followSet.isEmpty()]
${is}if self.outer_follow_set is not None:
${is}    new_follow_set = set(self.${nonterminal.followSetVarName}) | self.outer_follow_set
${is}    self.outer_follow_set = new_follow_set
  [/#if]
[/#if]
${is}try:
${is}    [#if !nonterminal.LHS?is_null && production.returnType != "void"]${nonterminal.LHS} = [/#if]self.parse_${nonterminal.name}(${globals.translateNonterminalArgs(nonterminal.args)})
   [#if !nonterminal.LHS?is_null && production.returnType = "void"]
${is}    try:
${is}        ${nonterminal.LHS} = self.peek_node()
${is}    except Exception:
${is}        ${nonterminal.LHS} = None
   [/#if]
   [#if !nonterminal.childName?is_null]
${is}    if self.build_tree:
${is}        child = self.peek_node()
${is}        name = '${nonterminal.childName}'
     [#if nonterminal.multipleChildren]
${is}        ${globals.currentNodeVariableName}.add_to_named_child_list(name, child)
     [#else]
${is}        ${globals.currentNodeVariableName}.set_named_child(name, child)
     [/#if]
   [/#if]
${is}finally:
${is}    self.pop_call_stack()
[#-- ${is}# DBG < BuildCodeNonTerminal ${indent} ${nonterminal.production.name} --]
[/#macro]


[#macro BuildCodeZeroOrOne zoo indent]
[#var is = ""?right_pad(indent)]
[#-- ${is}# DBG > BuildCodeZeroOrOne ${indent} ${zoo.nestedExpansion.class.simpleName} --]
    [#if zoo.nestedExpansion.class.simpleName = "ExpansionChoice"]
${BuildCode(zoo.nestedExpansion, indent)}
    [#else]
${is}if ${ExpansionCondition(zoo.nestedExpansion)}:
${BuildCode(zoo.nestedExpansion, indent + 4)}
    [/#if]
[#-- ${is}# DBG < BuildCodeZeroOrOne ${indent} ${zoo.nestedExpansion.class.simpleName} --]
[/#macro]

[#var inFirstVarName = "", inFirstIndex =0]

[#macro BuildCodeOneOrMore oom indent]
[#var is = ""?right_pad(indent)]
[#-- ${is}# DBG > BuildCodeOneOrMore ${indent} --]
[#var nestedExp=oom.nestedExpansion, prevInFirstVarName = inFirstVarName/]
   [#if nestedExp.simpleName = "ExpansionChoice"]
     [#set inFirstVarName = "inFirst" + inFirstIndex, inFirstIndex = inFirstIndex +1 /]
${is}${inFirstVarName} = True
   [/#if]
${is}while True:
${RecoveryLoop(oom, indent + 4)}
      [#if nestedExp.simpleName = "ExpansionChoice"]
${is}    ${inFirstVarName} = False
      [#else]
${is}    if not (${ExpansionCondition(oom.nestedExpansion)}): break
      [/#if]
   [#set inFirstVarName = prevInFirstVarName /]
[#-- ${is}# DBG < BuildCodeOneOrMore ${indent} --]
[/#macro]

[#macro BuildCodeZeroOrMore zom indent]
[#var is = ""?right_pad(indent)]
[#-- ${is}# DBG > BuildCodeZeroOrMore ${indent} --]
${is}while True:
       [#if zom.nestedExpansion.class.simpleName != "ExpansionChoice"]
${is}    if not (${ExpansionCondition(zom.nestedExpansion)}): break
       [/#if]
       [@RecoveryLoop zom indent+4 /]
[#-- ${is}# DBG < BuildCodeZeroOrMore ${indent} --]
[/#macro]

[#macro RecoveryLoop loopExpansion indent]
[#var is = ""?right_pad(indent)]
[#-- ${is}# DBG > RecoveryLoop ${indent} --]
[#if !settings.faultTolerant || !loopExpansion.requiresRecoverMethod]
${BuildCode(loopExpansion.nestedExpansion, indent)}
[#else]
[#var initialTokenVarName = "initialToken" + CU.newID()]
${is}${initialTokenVarName} = self.last_consumed_token
${is}try:
${BuildCode(loopExpansion.nestedExpansion, indent + 4)}
${is}except ParseException as pe:
${is}    logger.exception('Hit a parsing exception: %s', pe)
${is}    if not self.is_tolerant: raise
${is}    if self.debug_fault_tolerant:
${is}        logger.info('Handling exception. Last consumed token: %s at: %s', self.last_consumed_token.image, self.last_consumed_token.location)
${is}    if ${initialTokenVarName} is self.last_consumed_token:
${is}        self.last_consumed_token = self.next_token(self.last_consumed_token)
${is}        # We have to skip a token in this spot or
${is}        # we'll be stuck in an infinite loop!
${is}        self.last_consumed_token.skipped = True
${is}        if self.debug_fault_tolerant:
${is}            logger.info('Skipping token %s at: %s', self.last_consumed_token.image, self.last_consumed_token.location)
${is}    if self.debug_fault_tolerant:
${is}        logger.info('Repeat re-sync for expansion at: ${loopExpansion.location?j_string}');
${is}    self.${loopExpansion.recoverMethodName}();
${is}    if self.pending_recovery: raise
   [/#if]
[#-- ${is}# DBG < RecoveryLoop ${indent} --]
[/#macro]

[#macro BuildCodeChoice choice indent]
[#var is = ""?right_pad(indent)]
[#-- ${is}# DBG > BuildCodeChoice ${indent} --]
   [#list choice.choices as expansion]
${is}${(expansion_index=0)?string("if", "elif")} (${ExpansionCondition(expansion)}):
${BuildCode(expansion, indent + 4)}
   [/#list]
   [#if choice.parent.simpleName == "ZeroOrMore"]
${is}else:
${is}    break
   [#elseif choice.parent.simpleName = "OneOrMore"]
${is}elif (${inFirstVarName}):
${is}    self.push_onto_call_stack('${currentProduction.name}', '${choice.inputSource?j_string}', ${choice.beginLine}, ${choice.beginColumn})
${is}    raise ParseException(self, expected=self.${choice.firstSetVarName})
${is}else:
${is}    break
   [#elseif choice.parent.simpleName != "ZeroOrOne"]
${is}else:
${is}    self.push_onto_call_stack('${currentProduction.name}', '${choice.inputSource?j_string}', ${choice.beginLine}, ${choice.beginColumn})
${is}    raise ParseException(self, expected=self.${choice.firstSetVarName})
   [/#if]
[#-- ${is}# DBG < BuildCodeChoice ${indent} --]
[/#macro]

[#--
     Macro to generate the condition for entering an expansion
     including the default single-token lookahead
--]
[#macro ExpansionCondition expansion]
[#if expansion.requiresPredicateMethod]${ScanAheadCondition(expansion)}[#else]${SingleTokenCondition(expansion)}[/#if][#t]
[/#macro]


[#-- Generates code for when we need a scanahead --]
[#macro ScanAheadCondition expansion]
[#if expansion.lookahead?? && expansion.lookahead.LHS??](${expansion.lookahead.LHS} = [/#if][#if expansion.hasSemanticLookahead && !expansion.lookahead.semanticLookaheadNested](${globals.translateExpression(expansion.semanticLookahead)}) and [/#if]self.${expansion.predicateMethodName}()[#if expansion.lookahead?? && expansion.lookahead.LHS??])[/#if][#t]
[/#macro]


[#-- Generates code for when we don't need any scanahead routine --]
[#macro SingleTokenCondition expansion]
   [#if expansion.hasSemanticLookahead](${globals.translateExpression(expansion.semanticLookahead)}) and [/#if][#t]
   [#if expansion.firstSet.tokenNames?size =0 || expansion.lookaheadAmount ==0 || expansion.minimumSize=0]True[#elseif expansion.firstSet.tokenNames?size < 5][#list expansion.firstSet.tokenNames as name](self.next_token_type == ${name})[#if name_has_next] or [/#if][/#list][#t][#else](self.next_token_type in self.${expansion.firstSetVarName})[/#if][#t]
[/#macro]

[#macro BuildAssertionCode assertion indent]
[#var is = ""?right_pad(indent)]
[#var optionalPart = ""]
[#if assertion.messageExpression??]
  [#set optionalPart = " + " + globals.translateExpression(assertion.messageExpression)]
[/#if]
[#var assertionMessage = "Assertion at: " + assertion.location?j_string + " failed."]
[#if assertion.assertionExpression??]
${is}if not (${globals.translateExpression(assertion.assertionExpression)}):
${is}    self.fail("${assertionMessage}"${optionalPart})
[/#if]
[#if assertion.expansion??]
${is}if [#if !assertion.expansionNegated]not [/#if]self.${assertion.expansion.scanRoutineName}():
${is}    self.fail("${assertionMessage}"${optionalPart})
[/#if]
[/#macro]

[#--
   Macro to build routines that scan up to the start of an expansion
   as part of a recovery routine
--]
[#macro BuildRecoverRoutines]
   [#list grammar.expansionsNeedingRecoverMethod as expansion]
    def ${expansion.recoverMethodName}(self):
        initial_token = self.last_consumed_token
        skipped_tokens = []
        success = False

        while self.last_consumed_token.type != EOF:
[#if expansion.simpleName = "OneOrMore" || expansion.simpleName = "ZeroOrMore"]
            if (${ExpansionCondition(expansion.nestedExpansion)}):
[#else]
            if (${ExpansionCondition(expansion)}):
[/#if]
                success = True
                break
             [#if expansion.simpleName = "ZeroOrMore" || expansion.simpleName = "OneOrMore"]
               [#var followingExpansion = expansion.followingExpansion]
               [#list 1..1000000 as unused]
                [#if followingExpansion?is_null][#break][/#if]
                [#if followingExpansion.maximumSize >0]
                 [#if followingExpansion.simpleName = "OneOrMore" || followingExpansion.simpleName = "ZeroOrOne" || followingExpansion.simpleName = "ZeroOrMore"]
                if (${ExpansionCondition(followingExpansion.nestedExpansion)}):
                 [#else]
                if (${ExpansionCondition(followingExpansion)}):
                 [/#if]
                    success = True
                    break
                [/#if]
                [#if !followingExpansion.possiblyEmpty][#break][/#if]
                [#if followingExpansion.followingExpansion?is_null]
                if self.outer_follow_set is not None:
                    if self.next_token_type() in self.outer_follow_set:
                        success = True
                        break
                 [#break/]
                [/#if]
                [#set followingExpansion = followingExpansion.followingExpansion]
               [/#list]
             [/#if]
            self.last_consumed_token = self.next_token(self.last_consumed_token)
            skipped_tokens.append(self.last_consumed_token)
        if not success and skipped_tokens:
             self.last_consumed_token = initial_token
        if success and skipped_tokens:
            iv = InvalidNode(self)
            for tok in skipped_tokens:
                iv.add_child(tok)
            if self.debug_fault_tolerant:
                logger.info('Skipping %s tokens starting at: %s', len(skipped_tokens), skipped_tokens[0].location)
            self.push_node(iv)
        self.pending_recovery = not success

   [/#list]
[/#macro]
