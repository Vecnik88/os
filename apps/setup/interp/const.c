/*++

Copyright (c) 2015 Minoca Corp. All Rights Reserved

Module Name:

    const.c

Abstract:

    This module implements support for variable initializers.

Author:

    Evan Green 14-Oct-2015

Environment:

    POSIX

--*/

//
// ------------------------------------------------------------------- Includes
//

#include <assert.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

#include "../setup.h"
#include <minoca/lib/yy.h>

//
// ---------------------------------------------------------------- Definitions
//

//
// ------------------------------------------------------ Data Type Definitions
//

//
// ----------------------------------------------- Internal Function Prototypes
//

//
// -------------------------------------------------------------------- Globals
//

//
// ------------------------------------------------------------------ Functions
//

INT
SetupVisitListElementList (
    PSETUP_INTERPRETER Interpreter,
    PSETUP_NODE Node,
    PSETUP_OBJECT *Result
    )

/*++

Routine Description:

    This routine evaluates a list element list.

Arguments:

    Interpreter - Supplies a pointer to the interpreter.

    Node - Supplies a pointer to the node.

    Result - Supplies a pointer where a pointer to the evaluation will be
        returned. It is the caller's responsibility to release this reference.

Return Value:

    0 on success.

    Returns an error number on catastrophic failure.

--*/

{

    LONG Index;
    PSETUP_OBJECT List;
    PPARSER_NODE ParseNode;
    INT Status;

    ParseNode = Node->ParseNode;
    List = SetupCreateList(NULL, ParseNode->NodeCount);
    if (List == NULL) {
        return ENOMEM;
    }

    //
    // Add each entry in the element list to the dictionary.
    //

    for (Index = 0; Index < ParseNode->NodeCount; Index += 1) {
        Status = SetupListSetElement(List, Index, Node->Results[Index]);
        if (Status != 0) {
            SetupObjectReleaseReference(List);
            return Status;
        }
    }

    *Result = List;
    return 0;
}

INT
SetupVisitList (
    PSETUP_INTERPRETER Interpreter,
    PSETUP_NODE Node,
    PSETUP_OBJECT *Result
    )

/*++

Routine Description:

    This routine evaluates a list constant.

Arguments:

    Interpreter - Supplies a pointer to the interpreter.

    Node - Supplies a pointer to the node.

    Result - Supplies a pointer where a pointer to the evaluation will be
        returned. It is the caller's responsibility to release this reference.

Return Value:

    0 on success.

    Returns an error number on catastrophic failure.

--*/

{

    PPARSER_NODE ParseNode;

    ParseNode = Node->ParseNode;

    //
    // If it's an empty list, create it now. Otherwise by the time this
    // node is evaluated the list element list has already fully formed the
    // dictionary.
    //

    if (ParseNode->NodeCount == 0) {
        *Result = SetupCreateList(NULL, 0);
        if (*Result == NULL) {
            return ENOMEM;
        }

    } else {
        *Result = Node->Results[0];
        Node->Results[0] = NULL;
    }

    return 0;
}

INT
SetupVisitDictElement (
    PSETUP_INTERPRETER Interpreter,
    PSETUP_NODE Node,
    PSETUP_OBJECT *Result
    )

/*++

Routine Description:

    This routine evaluates a dictionary element.

Arguments:

    Interpreter - Supplies a pointer to the interpreter.

    Node - Supplies a pointer to the node.

    Result - Supplies a pointer where a pointer to the evaluation will be
        returned. It is the caller's responsibility to release this reference.

Return Value:

    0 on success.

    Returns an error number on catastrophic failure.

--*/

{

    PPARSER_NODE ParseNode;

    ParseNode = Node->ParseNode;

    assert(ParseNode->NodeCount == 2);

    *Result = SetupCreateList(Node->Results, 2);
    if (*Result == NULL) {
        return ENOMEM;
    }

    return 0;
}

INT
SetupVisitDictElementList (
    PSETUP_INTERPRETER Interpreter,
    PSETUP_NODE Node,
    PSETUP_OBJECT *Result
    )

/*++

Routine Description:

    This routine evaluates a dictionary element list.

Arguments:

    Interpreter - Supplies a pointer to the interpreter.

    Node - Supplies a pointer to the node.

    Result - Supplies a pointer where a pointer to the evaluation will be
        returned. It is the caller's responsibility to release this reference.

Return Value:

    0 on success.

    Returns an error number on catastrophic failure.

--*/

{

    PSETUP_OBJECT Dict;
    ULONG Index;
    PSETUP_LIST List;
    PPARSER_NODE ParseNode;
    INT Status;

    ParseNode = Node->ParseNode;
    Dict = SetupCreateDict(NULL);
    if (Dict == NULL) {
        return ENOMEM;
    }

    //
    // Add each entry in the element list to the dictionary. Each child node
    // is a dictionary element, which contains a list of the key and value.
    //

    for (Index = 0; Index < ParseNode->NodeCount; Index += 1) {
        List = (PSETUP_LIST)(Node->Results[Index]);

        assert(List->Header.Type == SetupObjectList);

        Status = SetupDictSetElement(Dict, List->Array[0], List->Array[1]);
        if (Status != 0) {
            SetupObjectReleaseReference(Dict);
            return Status;
        }
    }

    *Result = Dict;
    return 0;
}

INT
SetupVisitDict (
    PSETUP_INTERPRETER Interpreter,
    PSETUP_NODE Node,
    PSETUP_OBJECT *Result
    )

/*++

Routine Description:

    This routine evaluates a dictionary constant.

Arguments:

    Interpreter - Supplies a pointer to the interpreter.

    Node - Supplies a pointer to the node.

    Result - Supplies a pointer where a pointer to the evaluation will be
        returned. It is the caller's responsibility to release this reference.

Return Value:

    0 on success.

    Returns an error number on catastrophic failure.

--*/

{

    PPARSER_NODE ParseNode;

    ParseNode = Node->ParseNode;

    //
    // If it's an empty dictionary, create it now. Otherwise by the time this
    // node is evaluated the element list has already fully formed the
    // dictionary.
    //

    if (ParseNode->NodeCount == 0) {
        *Result = SetupCreateDict(NULL);
        if (*Result == NULL) {
            return ENOMEM;
        }

    } else {
        *Result = Node->Results[0];
        Node->Results[0] = NULL;
    }

    return 0;
}

INT
SetupVisitPrimaryExpression (
    PSETUP_INTERPRETER Interpreter,
    PSETUP_NODE Node,
    PSETUP_OBJECT *Result
    )

/*++

Routine Description:

    This routine evaluates a primary expression.

Arguments:

    Interpreter - Supplies a pointer to the interpreter.

    Node - Supplies a pointer to the node.

    Result - Supplies a pointer where a pointer to the evaluation will be
        returned. It is the caller's responsibility to release this reference.

Return Value:

    0 on success.

    Returns an error number on catastrophic failure.

--*/

{

    PSTR After;
    CHAR Character;
    PSTR Destination;
    ULONG Index;
    LONGLONG Integer;
    PSETUP_OBJECT Name;
    PPARSER_NODE ParseNode;
    PSTR Source;
    INT Status;
    PLEXER_TOKEN Token;
    PSTR TokenString;
    PSETUP_OBJECT Value;

    Name = NULL;
    ParseNode = Node->ParseNode;
    Value = NULL;

    //
    // It's a dictionary or a list, just return it.
    //

    if (ParseNode->NodeCount != 0) {

        assert(ParseNode->NodeCount == 1);

        Value = Node->Results[0];
        Node->Results[0] = NULL;

    //
    // It's an identifier, constant, or string literal.
    //

    } else {

        assert(ParseNode->TokenCount == 1);

        Token = ParseNode->Tokens[0];
        TokenString = Node->Script->Data + Token->Position;
        switch (Token->Value) {

        //
        // Look up the variable value.
        //

        case SetupTokenIdentifier:
            Name = SetupCreateString(TokenString, Token->Size);
            if (Name == NULL) {
                Status = ENOMEM;
                goto VisitPrimaryExpressionEnd;
            }

            Value = SetupGetVariable(Interpreter, Name);

            //
            // If the variable does not exist, create it now.
            //

            if (Value == NULL) {
                Value = SetupCreateInteger(0);
                if (Value == NULL) {
                    Status = ENOMEM;
                    goto VisitPrimaryExpressionEnd;
                }

                Status = SetupSetVariable(Interpreter, Name, Value);
                if (Status != 0) {
                    goto VisitPrimaryExpressionEnd;
                }
            }

            break;

        case SetupTokenHexInteger:
            Integer = strtoull(TokenString, &After, 16);
            Value = SetupCreateInteger(Integer);
            break;

        case SetupTokenOctalInteger:
            Integer = strtoull(TokenString, &After, 8);
            Value = SetupCreateInteger(Integer);
            break;

        case SetupTokenDecimalInteger:
            Integer = strtoull(TokenString, &After, 10);
            Value = SetupCreateInteger(Integer);
            break;

        case SetupTokenString:

            assert((*TokenString == '"') && (Token->Size >= 2));

            Value = SetupCreateString(TokenString + 1, Token->Size - 1);
            if (Value == NULL) {
                break;
            }

            //
            // Convert the escaped C string into a binary string.
            //

            Source = Value->String.String;
            Destination = Source;
            while (*Source != '"') {
                if (*Source == '\\') {
                    Source += 1;
                    Character = *Source;
                    Source += 1;
                    switch (Character) {
                    case 'r':
                        *Destination = '\r';
                        break;

                    case 'n':
                        *Destination = '\n';
                        break;

                    case 'f':
                        *Destination = '\f';
                        break;

                    case 'v':
                        *Destination = '\v';
                        break;

                    case 't':
                        *Destination = '\t';
                        break;

                    case 'a':
                        *Destination = '\a';
                        break;

                    case 'b':
                        *Destination = '\b';
                        break;

                    case 'x':
                        *Destination = 0;
                        for (Index = 0; Index < 2; Index += 1) {
                            if (!isxdigit(*Source)) {
                                break;
                            }

                            *Destination <<= 4;
                            if (isdigit(*Source)) {
                                *Destination += *Source - '0';

                            } else {
                                *Destination += tolower(*Source) - 'a' + 0xA;
                            }

                            Source += 1;
                        }

                        break;

                    case '0':
                    case '1':
                    case '2':
                    case '3':
                    case '4':
                    case '5':
                    case '6':
                    case '7':
                        *Destination = 0;
                        for (Index = 0; Index < 3; Index += 1) {
                            if (!((*Source >= '0') && (*Source <= '7'))) {
                                break;
                            }

                            *Destination <<= 3;
                            *Destination += *Source - '0';
                        }

                        break;

                    default:
                        *Destination = Character;
                        break;
                    }

                    Destination += 1;

                } else {
                    *Destination = *Source;
                    Destination += 1;
                    Source += 1;
                }
            }

            assert(Destination <= Source);

            *Destination = '\0';
            Destination += 1;
            Value->String.Size = Destination - Value->String.String;
            break;
        }

        if (Value == NULL) {
            Status = ENOMEM;
            goto VisitPrimaryExpressionEnd;
        }
    }

    Status = 0;

VisitPrimaryExpressionEnd:
    if (Status != 0) {
        if (Value != NULL) {
            SetupObjectReleaseReference(Value);
            Value = NULL;
        }
    }

    if (Name != NULL) {
        SetupObjectReleaseReference(Name);
    }

    *Result = Value;
    return 0;
}

INT
SetupVisitStatementList (
    PSETUP_INTERPRETER Interpreter,
    PSETUP_NODE Node,
    PSETUP_OBJECT *Result
    )

/*++

Routine Description:

    This routine evaluates a statement list.

Arguments:

    Interpreter - Supplies a pointer to the interpreter.

    Node - Supplies a pointer to the node.

    Result - Supplies a pointer where a pointer to the evaluation will be
        returned. It is the caller's responsibility to release this reference.

Return Value:

    0 on success.

    Returns an error number on catastrophic failure.

--*/

{

    //
    // Statement lists are nothing but side effects.
    //

    return 0;
}

INT
SetupVisitTranslationUnit (
    PSETUP_INTERPRETER Interpreter,
    PSETUP_NODE Node,
    PSETUP_OBJECT *Result
    )

/*++

Routine Description:

    This routine evaluates a translation unit.

Arguments:

    Interpreter - Supplies a pointer to the interpreter.

    Node - Supplies a pointer to the node.

    Result - Supplies a pointer where a pointer to the evaluation will be
        returned. It is the caller's responsibility to release this reference.

Return Value:

    0 on success.

    Returns an error number on catastrophic failure.

--*/

{

    //
    // Translation units are nothing but side effects.
    //

    return 0;
}

//
// --------------------------------------------------------- Internal Functions
//

