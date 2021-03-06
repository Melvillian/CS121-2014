//
//  Database.m
//  Glossolalia
//
//  Created by Paul on 2/13/2014
//  Copyright (c) 2014 Harvey Mudd College. All rights reserved.
//

#import "Database.h"

@implementation Database

static sqlite3 *db;

static sqlite3_stmt *createEntries;
static sqlite3_stmt *fetchEntries;
static sqlite3_stmt *insertEntry;
static sqlite3_stmt *deleteEntry;
static sqlite3_stmt *updateEntry;

+ (void)createEditableCopyOfDatabaseIfNeeded
{
    BOOL success;

    // allocate future error message (if necessary)
    NSError *error;
    
    // look for an existing database file and grab the file
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentDirectory = [paths objectAtIndex:0];
    NSString *writableDBPath = [documentDirectory stringByAppendingPathComponent:@"entries.sql"];
    success = [fileManager fileExistsAtPath:writableDBPath];
    if (success) return;
    
    // if failed to find one, copy the empty entries database into the location
    NSString *defaultDBPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"entries.sql"];
    
    // send error message if we could not create the entries.sql file
    success = [fileManager copyItemAtPath:defaultDBPath toPath:writableDBPath error:&error];
    if (!success) {
        NSAssert1(0, @"FAILED to create writable database file with message, '%@'.", [error localizedDescription]);
    }
}

+ (void)initDatabase
{
    // create the statement strings
    const char *createEntriesString = "CREATE TABLE IF NOT EXISTS entries (rowid INTEGER PRIMARY KEY AUTOINCREMENT, english TEXT, spanish TEXT, photo BLOB, phrase INTEGER)";
    const char *fetchEntriesString = "SELECT * FROM entries";
    const char *insertEntryString = "INSERT INTO entries (english, spanish, photo, phrase) VALUES (?, ?, ?, ?)";
    const char *deleteEntryString = "DELETE FROM entries WHERE rowid=?";
    
    // create the path to the database
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentDirectory = [paths objectAtIndex:0];
    NSString *path = [documentDirectory stringByAppendingPathComponent:@"entries.sql"];
    
    // open the database connection
    if (sqlite3_open([path UTF8String], &db)) {
        if (consoleSuite) {
            NSLog(@"ERROR opening the db");
        }
    }
    
    //init table statement
    if (sqlite3_prepare_v2(db, createEntriesString, -1, &createEntries, NULL) != SQLITE_OK) {
        if (consoleSuite) {
            NSLog(@"Failed to prepare entries create table statement");
        }
    }
    
    // execute the table creation statement
    int success;
    success = sqlite3_step(createEntries);
    sqlite3_reset(createEntries);
    if (success != SQLITE_DONE) {
        if (consoleSuite) {
            NSLog(@"ERROR: failed to create entries table");
        }
    }
    
    //init retrieval statement
    if (sqlite3_prepare_v2(db, fetchEntriesString, -1, &fetchEntries, NULL) != SQLITE_OK) {
        if (consoleSuite) {
            NSLog(@"ERROR: failed to prepare entries fetching statement");
        }
    }
    
    //init insertion statement
    if (sqlite3_prepare_v2(db, insertEntryString, -1, &insertEntry, NULL) != SQLITE_OK) {
        if (consoleSuite) {
            NSLog(@"ERROR: failed to prepare entry inserting statement");
        }
    }
    
    // init deletion statement
    if (sqlite3_prepare_v2(db, deleteEntryString, -1, &deleteEntry, NULL) != SQLITE_OK) {
        if (consoleSuite) {
            NSLog(@"ERROR: failed to prepare delete entry statement");
        }
    }
}

+(NSMutableArray *)fetchAllEntries
{
    // array of entries to be returned
    NSMutableArray *ret = [NSMutableArray arrayWithCapacity:0];
    
    // keep count of phrases
    int phraseCount = 0;
    int wordCount = 0;
    
    while (sqlite3_step(fetchEntries) == SQLITE_ROW) {
        
        // query columns from fetch statement
        char *englishChars = (char *) sqlite3_column_text(fetchEntries, 1);
        char *spanishChars = (char *) sqlite3_column_text(fetchEntries, 2);
        
        // convert image blob to UIImage
        int len = sqlite3_column_bytes(fetchEntries, 3);
        NSData *imageData = [[NSData alloc] initWithBytes: sqlite3_column_blob(fetchEntries, 3) length: len];
        UIImage *image = [[UIImage alloc] initWithData:imageData];
        
        // grab the phrase column, keep track of how many phrases are encountered
        bool phrase = false;
        int phraseBit = sqlite3_column_int(fetchEntries, 4);
        if (phraseBit == 1) {
            phrase = true;
            ++phraseCount;
        }
        bool word = !phrase;
        if (word) {
            ++wordCount;
        }
        
        // convert englush and spanish words to NSStrings
        NSString *english = [NSString stringWithUTF8String:englishChars];
        NSString *spanish = [NSString stringWithUTF8String:spanishChars];
        
        // create entry object
        GADataEntry *temp = [[GADataEntry alloc] initWithEnglish:english andSpanish:spanish andImage:image andPhrase:phrase];
        
        // add the entry object to our return array depending on whether or not it is a word/phrase
        if (phrase && !usePhrases) {
            continue;
        }
        else if (word && !useWords) {
            continue;
        }
        else {
            [ret addObject:temp];
        }
    }
        
    // reset the statement, return the array
    sqlite3_reset(fetchEntries);
    return ret;
    
}

+(void)deleteEntry:(int)rowid
{
    // bind the row id, step the statement, reset the statement, check for error
    sqlite3_bind_int(deleteEntry, 1, rowid);
    int success = sqlite3_step(deleteEntry);
    sqlite3_reset(deleteEntry);
    if (success != SQLITE_DONE) {
        if (consoleSuite) {
            NSLog(@"ERROR: failed to delete entry");
        }
    }
}

+(void)eraseAllEntries
{
    // TODO- enable delete to work properly on the exact number of entries
    NSMutableArray *array = [Database fetchAllEntries];
    int numEntries = [array count];
    
    // grab all of the entries, get a count of how many we have, and delete them one-by-one
    if (consoleSuite) {
        NSLog(@"erasing all database entries");
    }
    for(int i = 1; i < 100000; ++i){
        [Database deleteEntry:i];
    }
}

+(void)saveEntryWithEnglish:(NSString*)english andSpanish:(NSString*)spanish andImage:(UIImage *)image andPhrase:(bool)phrase
{
    // bind data to the statement
    sqlite3_bind_text(insertEntry, 1, [english UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(insertEntry, 2, [spanish UTF8String], -1, SQLITE_TRANSIENT);
    
    NSData *imageData = [NSData dataWithData:UIImageJPEGRepresentation(image, .7)];
    sqlite3_bind_blob(insertEntry, 3, [imageData bytes], [imageData length], SQLITE_TRANSIENT);
    
    int phraseInt = 0;
    if (phrase)
        phraseInt = 1;
    sqlite3_bind_int(insertEntry, 4, phraseInt);
    
    // insert into the database
    int success = sqlite3_step(insertEntry);
    sqlite3_reset(insertEntry);
    if (success != SQLITE_DONE) {
        if (consoleSuite) {
            NSLog(@"ERROR: failed to insert entry");
        }
    }
}

+(void)saveEntry:(GADataEntry*)dataEntry
{
    // bind data to the statement
    sqlite3_bind_text(insertEntry, 1, [dataEntry.english UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(insertEntry, 2, [dataEntry.spanish UTF8String], -1, SQLITE_TRANSIENT);
    
    NSData *imageData = [NSData dataWithData:UIImageJPEGRepresentation(dataEntry.image, .7)];
    sqlite3_bind_blob(insertEntry, 3, [imageData bytes], [imageData length], SQLITE_TRANSIENT);
    
    bool phrase = [dataEntry phrase];
    int phraseInt = 0;
    if (phrase)
        phraseInt = 1;
    sqlite3_bind_int(insertEntry, 4, phraseInt);
    
    // insert into the database
    int success = sqlite3_step(insertEntry);
    sqlite3_reset(insertEntry);
    if (success != SQLITE_DONE) {
        if (consoleSuite) {
            NSLog(@"ERROR: failed to insert entry");
        }
    }
}

+(void)updateDatabase
{
    // first erase all of the database entries, then make the HTTP request
    [Database eraseAllEntries];
    DatabaseCaller *updateCall = [[DatabaseCaller alloc] initForCallwithTarget:self andAction:@selector(addEntries:) andTesting:FALSE];
}

+(void)updateDatabaseForTesting
{
    // first erase all of the database entries, then make the HTTP request
    [Database eraseAllEntries];
    DatabaseCaller *updateCall = [[DatabaseCaller alloc] initForCallwithTarget:self andAction:@selector(addEntriesForTesting:) andTesting:TRUE];
    
}

+(void)addEntries:(NSMutableArray*)array
{
    // add an entire array of entries to the database
    if (consoleSuite) {
        NSLog(@"There are %d entries in the database", [array count]);
    }
    for(NSMutableDictionary *dict in array) {
        NSString *english = [dict objectForKey:@"English"];
        NSString *spanish = [dict objectForKey:@"Spanish"];
        
        NSString *phraseStr = [dict objectForKey:@"Phrase"];
        int phraseInt = [phraseStr intValue];
        bool phrase = NO;
        if (phraseInt == 1) {
            phrase = YES;
        }
        
        UIImage *image = nil;
        
        [Database saveEntryWithEnglish:english andSpanish:spanish andImage:image andPhrase:phrase];
    }
    if (consoleSuite) {
        NSLog(@"Database update complete");
    }
}

+(void)addEntriesForTesting:(NSMutableArray*)array
{
    // add an entire array of entries to the database
    if (consoleSuite) {
        NSLog(@"There are %d entries in the database", [array count]);
    }
    for (NSMutableDictionary *dict in array) {
        NSString *english = [dict objectForKey:@"English"];
        NSString *englishEx = [dict objectForKey:@"EnglishEx"];
        
        UIImage *image = nil;
        
        [Database saveEntryWithEnglish:english andSpanish:englishEx andImage:image andPhrase:true];
    }
    if (consoleSuite) {
        NSLog(@"Database update complete");
    }
}

+ (void)cleanUpDatabaseForQuit
{
    // finalize frees the compiled statements, close closes the database connection
    sqlite3_finalize(fetchEntries);
    sqlite3_finalize(insertEntry);
    sqlite3_finalize(deleteEntry);
    sqlite3_finalize(createEntries);
    sqlite3_finalize(updateEntry);
    sqlite3_close(db);
}

+(BOOL)isPopulated
{
    if ([[Database fetchAllEntries] count] == 0) {
        if (consoleSuite) {
            NSLog(@"database is not populated");
        }
        return FALSE;
    }
    else {
        if (consoleSuite) {
            NSLog(@"database is populated");
        }
        return TRUE;
    }
}

+(void)enableTesting
{
    if (consoleSuite) {
        NSLog(@"testing database enabled");
    }
    // first erase all of the database entries, then make the HTTP request with TRUE for testing
    [Database eraseAllEntries];
    DatabaseCaller *updateCall = [[DatabaseCaller alloc] initForCallwithTarget:self andAction:@selector(addEntries:) andTesting:TRUE];
}

+(void)disableTesting
{
    if (consoleSuite) {
        NSLog(@"testing database disabled");
    }
    // first erase all of the database entries, then make the HTTP request with FALSE for testing
    [Database eraseAllEntries];
    DatabaseCaller *updateCall = [[DatabaseCaller alloc] initForCallwithTarget:self andAction:@selector(addEntries:) andTesting:FALSE];
}
@end
