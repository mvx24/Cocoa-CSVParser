//
//  CSVParser.m
//
//  Created by Marc on 10/30/11.
//  Copyright 2011 Symbiotic Software LLC. All rights reserved.
//

#import "CSVParser.h"

@interface CSVParser (PrivateMethods)

- (void)setColumnNumber:(NSUInteger)number;

@end

@implementation CSVParser (PrivateMethods)

- (void)setColumnNumber:(NSUInteger)number
{
	columnNumber = number;
}

@end

BOOL processCSVLine(const char *csvLine, BOOL (*processField)(const char *, unsigned int, void *), void * data, int requiredFields)
{
	char *ptr, *startPtr, *endPtr, *newEndPtr;
	BOOL quotes = NO;
	unsigned int field = 0;
	unsigned int len = (unsigned int)strlen(csvLine);
	char *lineCopy;
	
	// Allocate a copy buffer that is double the size of the string
	lineCopy = (char *)malloc(sizeof(char) * ((len + 1) * 2));
	if(lineCopy == NULL) return NO;
	strncpy(lineCopy, csvLine, sizeof(char) * ((len + 1) * 2));
	
	for(startPtr = endPtr = lineCopy; *endPtr; ++endPtr)
	{
		if(*endPtr == '"')
		{
			if(quotes)
			{
				if(*(endPtr + 1) != '"')
				{
					quotes = NO;
				}
				else
				{
					for(ptr = endPtr; *ptr; ++ptr)
						*ptr = *(ptr + 1);
				}
				continue;
			}
			else
			{
				quotes = YES;
			}
		}
		else if((*endPtr == ',') && (quotes == NO))
		{
			*endPtr = 0;
			// Skip leading and trailing whitespace
			while((*startPtr == ' ') || (*startPtr == '\t') || (*startPtr == '\r') || (*startPtr == '\n')) ++startPtr;
			if(startPtr != endPtr)
				newEndPtr = endPtr - 1;
			else
				newEndPtr = endPtr;
			while((*newEndPtr == ' ') || (*newEndPtr == '\t') || (*newEndPtr == '\r') || (*newEndPtr == '\n')) --newEndPtr;
			if((*startPtr == '"') && (*newEndPtr == '"'))
			{
				*newEndPtr = 0;
				if(processField(startPtr + 1, field++, data) == NO)
					return NO;
				*newEndPtr = '"';
			}
			else
			{
				if(processField(startPtr, field++, data) == NO)
					return NO;
			}
			*endPtr = ',';
			startPtr = endPtr + 1;
		}
	}
	// Process the last field, skipping leading and trailing whitespace
	while((*startPtr == ' ') || (*startPtr == '\t') || (*startPtr == '\r') || (*startPtr == '\n')) ++startPtr;
	if(startPtr != endPtr)
		newEndPtr = endPtr - 1;
	else
		newEndPtr = endPtr;
	while((*newEndPtr == ' ') || (*newEndPtr == '\t') || (*newEndPtr == '\r') || (*newEndPtr == '\n')) --newEndPtr;
	if((*startPtr == '"') && (*newEndPtr == '"'))
	{
		*newEndPtr = 0;
		if(processField(startPtr + 1, field++, data) == NO)
			return NO;
		*newEndPtr = '"';
	}
	else
	{
		if(processField(startPtr, field++, data) == NO)
			return NO;
	}
	free(lineCopy);
	// If at the end of the record and still in quotes then this is a format error
	if(quotes)
		return NO;
	// Return YES if the record was complete according to the requirement
	if(requiredFields)
		return (field == requiredFields);
	
	return YES;
}

BOOL csvParserProcessField(const char *value, unsigned int column, void *csvParser)
{
	CSVParser *parser = (CSVParser *)csvParser;
	NSString *stringValue;
	
	[parser setColumnNumber:column];
	if([(NSObject *)parser.delegate respondsToSelector:@selector(parser:didParseValue:)])
	{
		stringValue = [[NSString alloc] initWithBytes:value length:strlen(value) encoding:NSUTF8StringEncoding];
		[parser.delegate parser:parser didParseValue:stringValue];
		[stringValue release];
	}
	return YES;
}

@implementation CSVParser

@synthesize delegate;

- (id)initWithString:(NSString *)csvDocument
{
	if(self = [super init])
	{
		csv = [csvDocument retain];
	}
	return self;
}

- (void)cleanup
{
	[columnNames release];
	columnNames = nil;
	lineNumber = 0;
	csvStr = NULL;
	if(lineBuffer != NULL)
		free(lineBuffer);
	lineBuffer = NULL;
	lineBufferSize = 0;
}

- (void)dealloc
{
	[csv release];
	[self cleanup];
	[super dealloc];
}

- (BOOL)getNextLine
{
	const char *ptr;
	BOOL quotes = NO;
	size_t lineSize;
	
	if(!*csvStr)
		return NO;
	
	// Find the complete line, ignoring line breaks inside quotes
	ptr = csvStr;
	while(1)
	{
		for(; *ptr && (*ptr != '\r') && (*ptr != '\n'); ++ptr)
		{
			if(*ptr == '"')
			{
				if(quotes && (*(ptr + 1) == '"'))
					++ptr;
				else
					quotes = !quotes;
			}
		}
		if(quotes && *ptr)
		{
			++ptr;
			continue;
		}
		break;
	}
	
	// Copy the line into a buffer
	lineSize = (ptr - csvStr) + 1;
	if(lineBufferSize < lineSize)
	{
		lineBufferSize = lineSize;
		if(lineBuffer != NULL)
			free(lineBuffer);
		lineBuffer = (char *)malloc(sizeof(char) * lineBufferSize);
	}
	
	memcpy(lineBuffer, csvStr, lineSize - 1);
	lineBuffer[lineSize - 1] = 0;
	
	// Advance to the start of the next line
	for(csvStr = ptr; ((*csvStr == '\r') || (*csvStr == '\n')); ++csvStr);
	
	return YES;
}

- (BOOL)parse
{
	if(self.delegate != nil)
	{
		if(![csv length])
		{
			if([(NSObject *)self.delegate respondsToSelector:@selector(parser:parseErrorOccurred:)])
				[self.delegate parser:self parseErrorOccurred:[NSError errorWithDomain:CSV_DOMAIN code:CSV_ERROR_NODATA userInfo:nil]];
			return NO;
		}
		
		// Start of parsing
		lineNumber = 0;
		csvStr = [csv UTF8String];
		if([(NSObject *)self.delegate respondsToSelector:@selector(parserDidStartDocument:)])
			[self.delegate parserDidStartDocument:self];
		
		// Parsing
		while([self getNextLine])
		{
			if(expectHeaders && (columnNames == nil))
			{
				id <CSVParserDelegate> parserDelegate = delegate;
				// Parse the first line to retrieve the headers
				delegate = (id<CSVParserDelegate>)self;
				columnNames = [NSMutableArray array];
				if(!processCSVLine(lineBuffer, csvParserProcessField, self, 0))
				{
					delegate = parserDelegate;
					if([(NSObject *)delegate respondsToSelector:@selector(parser:parseErrorOccurred:)])
						[delegate parser:self parseErrorOccurred:[NSError errorWithDomain:CSV_DOMAIN code:CSV_ERROR_BADFORMAT userInfo:nil]];
					[self cleanup];
					return NO;
				}
				if(expectedColumnsCount && ([columnNames count] != expectedColumnsCount))
				{
					delegate = parserDelegate;
					if([(NSObject *)delegate respondsToSelector:@selector(parser:parseErrorOccurred:)])
						[delegate parser:self parseErrorOccurred:[NSError errorWithDomain:CSV_DOMAIN code:CSV_ERROR_BADHEADER userInfo:nil]];
					[self cleanup];
					return NO;
				}
				// Restore the delegate and count the columns
				delegate = parserDelegate;
				columnNames = [[NSArray arrayWithArray:columnNames] retain];
				expectedColumnsCount = [columnNames count];
			}
			else
			{
				if([(NSObject *)self.delegate respondsToSelector:@selector(parserDidStartLine:)])
					[self.delegate parserDidStartLine:self];
				if(!processCSVLine(lineBuffer, csvParserProcessField, self, expectedColumnsCount))
				{
					if([(NSObject *)self.delegate respondsToSelector:@selector(parser:parseErrorOccurred:)])
						[self.delegate parser:self parseErrorOccurred:[NSError errorWithDomain:CSV_DOMAIN code:CSV_ERROR_BADFORMAT userInfo:nil]];
					[self cleanup];
					return NO;
				}
				if([(NSObject *)self.delegate respondsToSelector:@selector(parserDidEndLine:)])
					[self.delegate parserDidEndLine:self];
				++lineNumber;
			}
		}
		
		// End of parsing
		if([(NSObject *)self.delegate respondsToSelector:@selector(parserDidEndDocument:)])
			[self.delegate parserDidEndDocument:self];
		[self cleanup];
		return YES;
	}
	return NO;
}

- (void)setExpectedColumnsCount:(NSUInteger)expected
{
	expectedColumnsCount = expected;
}

- (void)setIsExpectingColumnsHeader:(BOOL)expecting
{
	expectHeaders = expecting;
}

- (NSArray *)columnNames
{
	return columnNames;
}

- (NSString *)line
{
	return [[[NSString alloc] initWithUTF8String:lineBuffer] autorelease];
}

- (NSInteger)lineNumber
{
	return lineNumber;
}

- (NSInteger)columnNumber
{
	return columnNumber;
}

- (void)parser:(CSVParser *)parser didParseValue:(NSString *)value
{
	[(NSMutableArray *)columnNames addObject:value];
}

@end
