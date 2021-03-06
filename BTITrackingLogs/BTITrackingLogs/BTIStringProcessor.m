//
//  BTIStringProcessor.m
//  BTITrackingLogs
//
//  Created by Brian Slick on 5/17/14.
//  Copyright (c) 2014 BriTer Ideas LLC. All rights reserved.
//

#import "BTIStringProcessor.h"

#import "NSString+BTIAdditions.h"

@interface BTIStringProcessor ()

// Private Properties
@property (nonatomic, copy) NSString *originalString;
@property (nonatomic, copy) NSString *logPrefix;
@property (nonatomic, copy) NSString *indentationToken;

@end

@implementation BTIStringProcessor

- (instancetype)initWithInputString:(NSString *)input
                     usingLogPrefix:(NSString *)logPrefix
{
    self = [super init];
    if (self)
    {
        [self setOriginalString:input];
        [self setLogPrefix:logPrefix];
    }
    return self;
}

- (NSString *)outputString
{
	NSLog(@">>> Entering <%p> %s <<<", self, __PRETTY_FUNCTION__);

    NSString *inputString = [self originalString];
	
	// Make sure the selection begins and ends with { }
	if ( (![inputString hasPrefix:@"{"]) || (![inputString hasSuffix:@"}"]) )
	{
		NSLog(@"<<< Leaving  <%p> %s >>> EARLY - Selection is not braces", self, __PRETTY_FUNCTION__);
		return inputString;
	}

    if ([[self logPrefix] length] == 0)
    {
        NSLog(@"<<< Leaving  <%p> %s >>> EARLY - No prefix provided", self, __PRETTY_FUNCTION__);
        return inputString;
    }
    
    NSString *indent = [inputString indentationTokenBTI];
    [self setIndentationToken:indent];
    
    NSSet *legacyPrefixes = [NSSet setWithObjects:@"NSLog", @"BTITrackingLog", nil];
    NSString *activeModernPrefix = [self logPrefix];

    NSString *legacyEntryFormat = @">>> Entering <%p> %s <<<";
	NSString *modernEntryFormat = @">>> Entering <%p> %s <<<";
	
	NSString *legacyExitFormat = @"<<< Leaving  <%p> %s >>>";
	NSString *modernExitFormat = @"<<< Leaving  <%p> %s >>>";
	
	NSString *legacyFormatTokens = @"\", self, __PRETTY_FUNCTION__);";
	NSString *modernFormatTokens = @"\", self, __PRETTY_FUNCTION__);";

    // (@">>> Entering <%p> %s <<<", self, __PRETTY_FUNCTION__);
	NSString *modernEntryStringStub = [NSString stringWithFormat:@"(@\"%@%@", modernEntryFormat, modernFormatTokens];
    NSString *modernEntryString = [activeModernPrefix stringByAppendingString:modernEntryStringStub];

    // (@"<<< Leaving  <%p> %s >>>", self, __PRETTY_FUNCTION__);
	NSString *modernExitStringStub = [NSString stringWithFormat:@"(@\"%@%@", modernExitFormat, modernFormatTokens];
    NSString *modernExitString = [activeModernPrefix stringByAppendingString:modernExitStringStub];

    // (@"<<< Leaving  <%p> %s >>> EARLY - <reason not specified>", self, __PRETTY_FUNCTION__);
	NSString *modernEarlyExitStringStub = [NSString stringWithFormat:@"(@\"%@ EARLY - <#Reason Not Specified#>%@", modernExitFormat, modernFormatTokens];
	NSString *modernEarlyExitString = [activeModernPrefix stringByAppendingString:modernEarlyExitStringStub];

    NSString *modernExitPrefix = [NSString stringWithFormat:@"%@(@\"%@", activeModernPrefix, modernExitFormat];

    // Upgrade/Replace older logs
	
	NSMutableString *upgradeString = [NSMutableString stringWithString:inputString];

    [upgradeString replaceOccurrencesOfString:legacyEntryFormat withString:modernEntryFormat options:NSLiteralSearch range:NSMakeRange(0, [upgradeString length])];
	[upgradeString replaceOccurrencesOfString:legacyExitFormat withString:modernExitFormat options:NSLiteralSearch range:NSMakeRange(0, [upgradeString length])];
	[upgradeString replaceOccurrencesOfString:legacyFormatTokens withString:modernFormatTokens options:NSLiteralSearch range:NSMakeRange(0, [upgradeString length])];
    
    for (NSString *legacyPrefix in legacyPrefixes)
    {
        if ([legacyPrefix isEqualToString:activeModernPrefix])
        {
            continue;
        }
        
        NSString *standardEntryString = [legacyPrefix stringByAppendingString:modernEntryStringStub];
        NSString *standardExitString = [legacyPrefix stringByAppendingString:modernExitStringStub];

        [upgradeString replaceOccurrencesOfString:standardEntryString withString:modernEntryString options:NSLiteralSearch range:NSMakeRange(0, [upgradeString length])];
		[upgradeString replaceOccurrencesOfString:standardExitString withString:modernExitString options:NSLiteralSearch range:NSMakeRange(0, [upgradeString length])];
		
		NSString *oldEarlyExitString = [NSString stringWithFormat:@"%@(@\"%@", legacyPrefix, modernExitFormat];
		NSString *newEarlyExitString = [NSString stringWithFormat:@"%@(@\"%@", activeModernPrefix, modernExitFormat];
		
		[upgradeString replaceOccurrencesOfString:oldEarlyExitString withString:newEarlyExitString options:NSLiteralSearch range:NSMakeRange(0, [upgradeString length])];

    }

    // Loop over each line to determine where to insert tracking logs

    NSCharacterSet *whitespaceSet = [NSCharacterSet whitespaceCharacterSet];

    NSArray *originalLines = [upgradeString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    __block NSMutableArray *newLines = [NSMutableArray array];
	
	__block NSInteger scopeDepth = 0;
	__block NSMutableArray *blockDepth = [NSMutableArray array];

    [originalLines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger index, BOOL *stop) {
		
		NSLog(@"line        is: ---%@---", line);
		
		// Capture and trim leading whitespace
		NSString *trimmedLine = [line stringByTrimmingCharactersInSet:whitespaceSet];
		NSString *leadingWhitespace = @"";
		
		NSLog(@"trimmedLine is: ---%@---", trimmedLine);
		
		if ([trimmedLine length] == 0)		// Line is blank
		{
			[newLines addObject:line];
			return;
		}
		
		if ([line length] != [trimmedLine length])
		{
			NSRange originalRange = [line rangeOfString:trimmedLine];
			leadingWhitespace = [line substringToIndex:originalRange.location];
		}
		
		// Determine if scope depth (indenting) needs to change)
		
		BOOL isOpeningBrace = ([trimmedLine hasPrefix:@"{"] || [trimmedLine hasSuffix:@"{"]);
		BOOL isClosingBrace = ([trimmedLine hasPrefix:@"}"]);
		BOOL isStartOfBlock = ([trimmedLine rangeOfString:@"^"].location != NSNotFound);
		BOOL isInsideBlock = ([blockDepth count] > 0);
		
		if (isOpeningBrace)
		{
			scopeDepth++;
			if ( (isStartOfBlock) || (isInsideBlock) )
			{
				[blockDepth addObject:@YES];
			}
		}
		
		if (isClosingBrace)
		{
			scopeDepth--;
			if (isInsideBlock)
			{
				[blockDepth removeLastObject];
			}
		}
		
		if ([trimmedLine hasPrefix:@"return"])
		{
			// Determine if this is inside a block
			
			if (isInsideBlock)
			{
				[newLines addObject:line];
				return;
			}
			
			// Determine if this is the last return.  The final is handled separately after the loop.
			// Assumptions: Final return will either be next-to-last line or line before that.
			NSInteger supportedMargin = 3;
			
			if (index >= [originalLines count] - supportedMargin)
			{
				[newLines addObject:line];
				return;
			}
			
			// Determine if previous line already has a log
			
			NSString *previousLine = [newLines lastObject];
			NSString *trimmedPreviousLine = [previousLine stringByTrimmingCharactersInSet:whitespaceSet];
			
			if ([trimmedPreviousLine hasPrefix:modernExitPrefix])
			{
				[newLines addObject:line];
				return;
			}
			
			// Determine if return is not braced
            
            NSString *nextLine = [originalLines objectAtIndex:index + 1];
            NSString *trimmedNextLine = [nextLine stringByTrimmingCharactersInSet:whitespaceSet];
            
            if ([trimmedNextLine hasPrefix:@"}"])		// Has brace, just add the log
            {
                NSString *newWhiteSpace = [self whitespaceForScopeDepth:scopeDepth];
                
                [newLines addObject:[newWhiteSpace stringByAppendingString:modernEarlyExitString]];
                [newLines addObject:line];
                
                return;
            }
            else		// Does not have a brace, need to add braces
            {
                NSString *regularWhiteSpace = [self whitespaceForScopeDepth:scopeDepth];
                NSString *extraWhiteSpace = [self whitespaceForScopeDepth:scopeDepth + 1];
                
                BOOL isIfLineFound = NO;
                NSInteger index = [newLines count];
                for (NSString *newLine in [newLines reverseObjectEnumerator])
                {
                    index--;
                    
                    NSString *trimmedNewLine = [newLine stringByTrimmingCharactersInSet:whitespaceSet];
                    if ([trimmedNewLine hasPrefix:@"if"])
                    {
                        isIfLineFound = YES;
                        break;
                    }
                }
                
                if (isIfLineFound)
                {
                    [newLines insertObject:[regularWhiteSpace stringByAppendingString:@"{"] atIndex:index + 1];
                    [newLines addObject:[extraWhiteSpace stringByAppendingString:modernEarlyExitString]];
                    [newLines addObject:line];
                    [newLines addObject:[regularWhiteSpace stringByAppendingString:@"}"]];
                    
                    return;
                }
                else
                {
                    // Could not determine where to place opener.
                    
                    [newLines addObject:line];
                    
                    return;
                }
            }
		}
		
		[newLines addObject:line];
		
	}];
    
    // Add entering log
	
	{{
		BOOL shouldInsertLog = NO;
		BOOL shouldInsertBlankLine = NO;
		
		// Inspect first line
		if ([newLines count] > 1)
		{
			NSString *firstLine = [newLines objectAtIndex:1];
			NSString *trimmedFirstLine = [firstLine stringByTrimmingCharactersInSet:whitespaceSet];
			
			shouldInsertLog = ![trimmedFirstLine isEqualToString:modernEntryString];
		}
		
		if (shouldInsertLog)
		{
			[newLines insertObject:[[self indentationToken] stringByAppendingString:modernEntryString] atIndex:1];
		}
		
		// Inspect second line
		if ([newLines count] > 2)
		{
			NSString *secondLine = [newLines objectAtIndex:2];
			NSString *trimmedSecondLine = [secondLine stringByTrimmingCharactersInSet:whitespaceSet];
			
			shouldInsertBlankLine = ([trimmedSecondLine length] != 0);
		}
		
		if (shouldInsertBlankLine)
		{
			[newLines insertObject:@"" atIndex:2];
		}
	}}
	
	// Add final leaving log
	
	{{
		NSInteger returnLineIndex = NSNotFound;
        
		NSInteger index = [newLines count];
		NSInteger lastIndex = index - 1;
		NSInteger maxSupportedMarginIndex = index - 3;
		
		for (NSString *line in [newLines reverseObjectEnumerator])
		{
			index--;
			if (index <= maxSupportedMarginIndex)
				break;
			
			if ([line rangeOfString:@"return"].location != NSNotFound)
			{
				returnLineIndex = index;
				break;
			}
		}
		
		NSInteger targetLogIndex = (returnLineIndex == NSNotFound) ? lastIndex - 1 : MIN(lastIndex - 1, returnLineIndex - 1);
        
		NSString *logLine = [newLines objectAtIndex:targetLogIndex];
		NSString *trimmedLogLine = [logLine stringByTrimmingCharactersInSet:whitespaceSet];
		
		if (![trimmedLogLine isEqualToString:modernExitString])
		{
			[newLines insertObject:[[self indentationToken] stringByAppendingString:modernExitString] atIndex:targetLogIndex + 1];
            
			NSString *blankLine = [newLines objectAtIndex:targetLogIndex];
			NSString *trimmedBlankLine = [blankLine stringByTrimmingCharactersInSet:whitespaceSet];
			
			if ([trimmedBlankLine length] != 0)
			{
				[newLines insertObject:@"" atIndex:targetLogIndex + 1];
			}
		}
	}}
	
	NSString *returnString = [newLines componentsJoinedByString:@"\n"];

	NSLog(@"<<< Leaving  <%p> %s >>>", self, __PRETTY_FUNCTION__);
    return returnString;
}

- (NSString *)whitespaceForScopeDepth:(NSInteger)scopeDepth
{
	NSLog(@">>> Entering <%p> %s <<<", self, __PRETTY_FUNCTION__);

	NSString *whiteSpace = @"";
	
	for (int scopeCounter = 0; scopeCounter < scopeDepth; scopeCounter++)
	{
		whiteSpace = [whiteSpace stringByAppendingString:[self indentationToken]];
	}
	
	NSLog(@"<<< Leaving  <%p> %s >>>", self, __PRETTY_FUNCTION__);
	return whiteSpace;
}


@end
