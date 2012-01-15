//
//  CSVParser.h
//
//  Created by Marc on 10/30/11.
//  Copyright 2011 Symbiotic Software LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

#define CSV_DOMAIN				@"CSVParser"
#define CSV_ERROR_NODATA		1
#define CSV_ERROR_BADFORMAT		2
#define CSV_ERROR_BADHEADER		3

@class CSVParser;

@protocol CSVParserDelegate
@optional
- (void)parserDidStartDocument:(CSVParser *)parser;
- (void)parserDidEndDocument:(CSVParser *)parser;
- (void)parser:(CSVParser *)parser parseErrorOccurred:(NSError *)parseError;
- (void)parserDidStartLine:(CSVParser *)parser;
- (void)parserDidEndLine:(CSVParser *)parser;
- (void)parser:(CSVParser *)parser didParseValue:(NSString *)value;
@end

@interface CSVParser : NSObject
{
	id <CSVParserDelegate> delegate;
@private
	const char *csvStr;
	char *lineBuffer;
	size_t lineBufferSize;
	
	NSString *csv;
	NSUInteger expectedColumnsCount;
	BOOL expectHeaders;
	
	NSArray *columnNames;
	NSInteger lineNumber;
	NSInteger columnNumber;
}

@property (nonatomic, assign) id <CSVParserDelegate> delegate;

- (id)initWithString:(NSString *)csvDocument;
- (void)dealloc;
- (BOOL)parse;

- (void)setExpectedColumnsCount:(NSUInteger)expected;
- (void)setIsExpectingColumnsHeader:(BOOL)expecting;

- (NSArray *)columnNames;
// Line and line number starting at 0 with the first non-header line
- (NSString *)line;
- (NSInteger)lineNumber;
// 0-based column number
- (NSInteger)columnNumber;

@end
