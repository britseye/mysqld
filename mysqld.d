/*
* Copyright (C) 2009 Steve Teale
*
* This software is provided 'as-is', without any express or implied
* warranty.  In no event will the authors be held liable for any damages
* arising from the use of this software.
*
* Permission is granted to anyone to use this software for any purpose,
* including commercial applications, and to alter it and redistribute it
* freely, subject to the following restrictions:
*
* 1. The origin of this software must not be misrepresented; you must not
*    claim that you wrote the original software. If you use this software
*    in a product, an acknowledgment in the product documentation would be
*    appreciated but is not required.<p>
* 2. Altered source versions must be plainly marked as such, and must not be
*    misrepresented as being the original software.<p>
* 3. This notice may not be removed or altered from any source distribution.
*/

/**
 * A D wrapper for the MySQL C API (libmysqlclient/libmysql) - MySQLD. Source file mysqld.d.
 *
 * This module attempts to provide composite objects and methods that will allow a wide range of common database
 * operations, but be relatively easy to use. The design is a first attempt to illustrate the structure of a set of modules
 * to cover popular database systems and ODBC.
 *
 * It depends on myqsl.d, which is, except for three typedefs, a straight translation into D of the relevant
 * MySQL C API header files
 *
 * It does not aim to replace the latter. There's lots of stuff in there that is probably used rather infrequently.
 * If you need it, it is there for the calling.
 *
 * Neither does this version pretend to be comprehensive. At present, explicit support for MySQL stored procedures,
 * transactions, and multi-statement operations in general is missing.
 *
 * Its primary objects are:<ul>
 *    <li>Connection: <ul><li>Connection to the server, and querying and setting of server parameters.</li></ul></li>
 *    <li>Command:  Handling of SQL requests/queries/commands, with principal methods:
 *                      <ul><li>execSQL() - plain old SQL query.</li>
 *                      <li>execTuple() - get a set of values from a result row into a matching tuple of D variables.</li>
 *                      <li>execPrepared() - execute a prepared statement.</li>
 *                      <li>execResult() - execute a raw SQL statement and get a complete result set.</li>
 *                      <li>execSequence() - execute a raw SQL statement and handle the rows one at a time.</li>
 *                      <li>execPreparedResult() - execute a prepared statement and get a complete result set.</li>
 *                      <li>execPreparedSequence() - execute a prepared statement and handle the rows one at a time.</li>
 *                      <li>execFunction() - execute a stored function with D variables as input and output.
 *                      <li>execProcedure() - execute a stored procedure with D variables as input.
 *                      </li></ul>
 *    <li>ResultSet: <ul><li>A random access range of rows, where a Row is an array of variant.</li></ul>
 *    <li>ResultSequence: <ul><li>An input range of similar rows.</li></ul></li></ul>
 * It has currently only been compiled and unit tested on Ubuntu with D2.055, and the MySQL 5.5 client library.
 * The required MySQL header files were translated the hard way, since we don't have the benefit of an htod ln
 * a Linux environment. In the case of relatively complex library header file this is a potential source of
 * errors, since the fact that such a translation compiles is not a guarantee that it is correct. However, it seems to
 * survived all the unit tests I have tried so far.
 *
 * There are numerous examples of usage in the unittest sections.
 *
 * The file mysqld.sql, included with the module source code, can be used to generate the tables required by the unit tests.
 *
 * There is an outstanding issue with Connections. It seems that the MySQL client library embeds a description
 * of the Unix socket to be used for communication with 'localhost' that does not agree with the one used even by
 * some older servers which adopted a different path ages ago. This is currently hard coded into Connection.
 *
 * There is another issue with std.variant. This can not currently cope with structs of the size used by MySQL to
 * describe dates and times. The current version defines a modified variant - MyVariant that includes these types.
 */
module mysqld;

import mysql;
import errmsg;

import std.stdio;
import std.string;
import std.conv;
import std.c.string;
import std.range;
import std.variant;

// Note: One time struct is used by MySQL to handle time, date, datetime, and timestamp. This makes
// some operations in mysqld difficult or imposible, so mysql.d contains an alias and four typedefs as follows:
/*
struct st_mysql_time
{
   ...
}
alias st_mysql_time MYSQL_TIME;
typedef st_mysql_time MYSQL_DATE;
typedef st_mysql_time MYSQL_DATETIME;
typedef st_mysql_time MYSQL_TIMESTAMP;
typedef st_mysql_time MYSQL_TIMEDIFF;
*/

// 'Classic' MySQL delivers column values as strings. This function provides for their conversion to
// MYSQL_TIME
MYSQL_TIME toMyTime(string s, enum_field_types specific)
{
   MYSQL_TIME ts;

   void parseDate()
   {
      ts.year = parse!(uint)(s);
      munch(s, "-");
      ts.month = parse!(uint)(s);
      munch(s, "-");
      ts.day = parse!(uint)(s);
   }

   void parseTime()
   {
      ts.hour = parse!(uint)(s);
      munch(s, ":");
      ts.minute = parse!(uint)(s);
      munch(s, ":");
      ts.second = parse!(uint)(s);
      if (s.length)
      {
         munch(s, ":.");
         ts.second_part = parse!(uint)(s);
      }
   }

   switch (specific)
   {
      case enum_field_types.MYSQL_TYPE_DATE:
         parseDate();
         break;
      case enum_field_types.MYSQL_TYPE_TIME:
         parseTime();
         break;
      case enum_field_types.MYSQL_TYPE_DATETIME:
      case enum_field_types.MYSQL_TYPE_TIMESTAMP:
         parseDate();
         munch(s, " ");
         parseTime();
         break;
      default:
         break;
   }

   return ts;
}

alias VariantN!(maxSize!(creal, char[], void delegate(),
                     st_mysql_time, MYSQL_DATE, MYSQL_DATETIME, MYSQL_TIMESTAMP, MYSQL_TIMEDIFF)) MyVariant;

/**
 *  An exception type for MySQLD
 *
 * If the module encounters a problem it will throw an exception of type MySQLDException.
 */
class MySQLDException : Exception
{
   uint _errnum;
   char[] _errmsg;

   /**
    * An exception constructor from MySQL API error information.
    */
   this(MYSQL* h, string file, int line)
   {
      _errnum = mysql_errno(h);
      const char* err = mysql_error(h);
      _errmsg.length = strlen(err);
      strcpy(_errmsg.ptr, err);
      super(format("error #: (%d): %s", _errnum, _errmsg), file, line);
   }

   /**
    * An exception constructor from a string - used when MySQLD sees a problem.
    */
   this(string msg, string file, int line)
   {
      super(format("MySQLD Exception: %s", msg), file, line);
   }
}
/// MySQLDException AKA MyX
alias MySQLDException MyX;

/**
 * A class to encapsulate struct MYSQL and its associated functions and to allow connection to a database.
 *
 * It is likely that at some future stage of development, Connection will be an implementation of an interface
 * DBConnection (or similar).
 *
 * This is very thin wrapper stuff, but it is pre-requisite, so wrapped to some extent.
 */

 // Connection was going to be a struct so that its destructor could be called promptly when it went out of scope.
 // However there appears to be a compiler bug that prevents this from being done. An issue has been filed -
class Connection
{
private:
   MYSQL _mysql;
   MYSQL* _handle;
   alias _handle CH;
   MY_CHARSET_INFO _csi;    // Later - header file hell
   bool _auto, _inited;

   static string[] parseConnectionString(string cs)
   {
      string[] rv;
      rv.length = 4;
      string[] a = split(cs, ";");
      foreach (s; a)
      {
         string[] a2 = split(s, "=");
         if (a2.length != 2)
            throw new Exception("Bad connection string: " ~ cs);
         string name = strip(a2[0]);
         string val = strip(a2[1]);
         val ~= "\0";
         switch (name)
         {
            case "host":
               rv[0] = val;
               break;
            case "user":
               rv[1] = val;
               break;
            case "pwd":
               rv[2] = val;
               break;
            case "db":
               rv[3] = val;
               break;
            default:
               throw new Exception("Bad connection string: " ~ cs);
               break;
         }
      }
      return rv;
   }

   // Initialize the MySQL environment
   static this()
   {
      mysql_server_init(0, null, null);
   }

   ~this()
   {
      // Deallocate malloc'd memory provided by mysql_init()
      mysql_close(CH);
   }

   // Clean up the MySQL environment
   static ~this()
   {
      mysql_server_end();
   }

public:

   /**
    * Default constructor - Initialize Connection object
    */
   this()
   {
      if (_inited)
         return;
      _handle = &_mysql;
      mysql_init(&_mysql);
      _inited = true;
   }

   /**
    * Constructor to create an opened Connection
    *
    * Params:
    *   connectionString = &lt;host=hostname/IP>;user=username;pwd=password;db=database&gt;
    */
   this(string connectionString)
   {
      this();
      open(connectionString);
   }

   /**
    * Get connection handle
    *
    * Returns:
    *   Pointer to a MYSQL struct  - used by many mysql_xxx_xx() calls.
    */
   MYSQL* handle() { return CH; }

   /**
    * Change user.
    *
    * Params:
    *   user = user name
    *   password = password
    *   databse = database to use (optional)
    */
   void switchUser(string user, string password, string database = null)
   {
      mysql_change_user(CH, cast(char*) toStringz(user), cast(char*) toStringz(password),
                                                   ((database is null)? null: cast(char*) toStringz(database)));
   }

   /**
    * Get current character set info.
    *
    * Currently there is no other support for character set operations.
    */
   MY_CHARSET_INFO* charSetInfo()
   {
      mysql_get_character_set_info(CH, &_csi);
      return &_csi;
   }

   /**
    * Get a string showing the current server statistics.
    *
    * This and the following methods in the Connection class are MySQL specific, though several of them
    * might well be available from other databas implementations. A general purpose interface could
    * provide an LCD set, and a methos to populate a dictionary with implementation-specific stuff.
    *
    * Returns:
    *   A string like "Uptime: 6646  Threads: 2  Questions: 282  Slow queries: 0  Opens: 42  Flush tables: 1
    *                        Open tables: 1  Queries * per second avg: 0.42"
    */
   string stats()
   {
      char[] buf;
      const char* s = mysql_stat(CH);
      return s[0..strlen(s)].idup;
   }

   /**
    * Query for the current database
    *
    * Returns:
    *   The name of the current database.
    */
   string currentDB()
   {
      if (mysql_real_query(CH, cast(char*) "select DATABASE()\0".ptr, 17))
         throw new MyX(&_mysql, __FILE__, __LINE__);
      MYSQL_RES* res = mysql_store_result(CH);
      MYSQL_ROW row = mysql_fetch_row(res);
      string s = to!string(row[0]);
      mysql_free_result(res);
      return s;
   }

   /**
    * Get rid of a query result.
    *
    * Pulls any outstanding data from the server, then frees it. Use if you have executed a query but are only interested
    * in the status.
    */
   void skipResult()
   {
      MYSQL_RES* res = mysql_store_result(CH);
      if (res is null)
         return;
      mysql_free_result(res);
   }

   /**
    * Ping the server to make sure it is still there
    *
    * Returns:
    *   true if all is well.
    */
   bool serverOK()
   {

      int rv = mysql_ping(CH);
      return (rv == 0);
   }

   /**
    * Get the client version as a string.
    *
    * Returns:
    *   Version string.
    */
   string clientVersion()
   {
      const char* s = mysql_get_client_info();
      return to!string(s);
   }

   /**
    * Get the client version as a number
    *
    * Returns:
    *   Version number.
    */
   uint clientVersionNumber() { return mysql_get_client_version(); }

   /**
    * Determine what host we are connected to.
    *
    * Returns:
    *   A sring like "localhost via TCP/IP".
    */
   string hostInfo()
   {
      const char* s = mysql_get_host_info(CH);
      return to!string(s);
   }

   /**
    * Get the server version as a string.
    *
    * Returns:
    *   Version string.
    */
   string serverVersion()
   {
      const char* s = mysql_get_server_info(CH);
      return to!string(s);
   }

   /**
    * Get the server version as a number
    *
    * Returns:
    *   Version number.
    */
   uint serverVersionNumber() { return mysql_get_server_version(CH); }

   /**
    * Get the protocol that is in use
    *
    * Returns:
    *   ? not documented
    */
   uint protocol() { return mysql_get_proto_info(CH); }

   /**
    * Open a connection to a specified host.
    *
    * There's an outstanding issue here. It seems like the current client library and my server disagree about
    * the Unix socket to use for a localhost connection. At present I'm fudging the isue with a hard-coded
    * socket path. I'll maybe resolve this when I get round to upgrading my server, but it could well be a client
    * library issue, since the Unix socket actually used by the server is the 'new' version. The one the client
    * library says it can't find is the 'old' version.
    *
    * Params:
    *   cs = A connection string like host=hostname/IP;user=username;pwd=password;db=database;
    */
   void open(string cs)
   {
      string[] a = parseConnectionString(cs);
      MYSQL* rv = mysql_real_connect(CH, cast(char*) a[0].ptr, cast(char*) a[1].ptr, cast(char*) a[2].ptr, cast(char*) a[3].ptr,
                                          0, "/var/run/mysqld/mysqld.sock\0".ptr, CLIENT_MULTI_RESULTS | CLIENT_REMEMBER_OPTIONS);
      if (rv is null)
         throw new MyX(CH, __FILE__, __LINE__);
   }

   /**
    * Open a connection to a specified host/database.
    *
    * (Similar socket reservation)
    *
    * Params:
    *   host = Host name or IP address
    *   user = User name
    *   pwd = password
    *   db = Database name
    */
   void open(string host, string user,string pwd, string db)
   {
      MYSQL* rv = mysql_real_connect(CH, cast(char*) host.toStringz, cast(char*) user.toStringz,
                                       cast(char*) pwd.toStringz, cast(char*) db.toStringz,
                                       0, "/var/run/mysqld/mysqld.sock\0".ptr, CLIENT_MULTI_RESULTS | CLIENT_REMEMBER_OPTIONS);
      if (rv is null)
         throw new MyX(CH, __FILE__, __LINE__);
   }
   /**
    * Close the connection
    */
   void close() { mysql_close(CH); }

   /**
    * Determine the auto-commit mode
    *
    * Returns:
    *   true if auto-commit is on.
    */
   bool autoCommit() { return _auto; }
   /**
    * Set the auto-commit mode.
    *
    * Params:
    *   mode = true/false to set the new mode.
    * Returns:
    *   The previous mode.
    */
   bool autoCommit(bool mode) { bool old = _auto; mysql_autocommit(CH, mode? 1: 0); return old; }

   /**
    * Set a SQL command string to be executed on connection.
    *
    * See the MySQL documentation for mysql_options() for details of options that can be set.
    *
    * Params:
    *   sql = A SQL string.
    */
   void initialCommand(string sql)  { mysql_options(CH, mysql_option.MYSQL_INIT_COMMAND, cast(void*) toStringz(sql)); }

   /**
    * Tell the client to compress its communications.
    */
   void compress() { mysql_options(CH, mysql_option.MYSQL_OPT_COMPRESS, null); }

   /**
    * Modify the connection time-out period.
    *
    * Params:
    *   seconds = New value in seconds.
    */
   void connectTimeout(uint seconds) { mysql_options(CH, mysql_option.MYSQL_OPT_CONNECT_TIMEOUT, &seconds); }

   /**
    * Modify the time-out period for reads.
    *
    * Params:
    *   seconds = New value in seconds.
    */
   void readTimeout(uint seconds) { mysql_options(CH, mysql_option.MYSQL_OPT_READ_TIMEOUT, &seconds); }

   /**
    * Modify the time-out period for writes.
    *
    * Params:
    *   New value in seconds.
    */
   void writeTimeout(uint seconds) { mysql_options(CH, mysql_option.MYSQL_OPT_WRITE_TIMEOUT, &seconds); }

   /**
    * Tell the client to use a named pipe.
    *
    * A Windows option - named pipe is default for Linux
    */
   void useNamedPipe() { mysql_options(CH, mysql_option.MYSQL_OPT_NAMED_PIPE, null); }

   /**
    * Tell the client to attempt to reconnect if the connection is lost.
    *
    */
   void reconnect(bool tryReconnect) { mysql_options(CH, mysql_option.MYSQL_OPT_RECONNECT, &tryReconnect); }

   /**
    * Tell the server to report truncation if the buffer provided for an out parameter is not big enough.
    * Default in MySQL 5 is yes.
    *
    * Params:
    *    repoert = bool yes/no.
    */
   void reportTruncation(bool report) { mysql_options(CH, mysql_option.MYSQL_REPORT_DATA_TRUNCATION, &report); }

}

unittest
{
   immutable string host = "localhost";
   immutable string user = "user";
   immutable string pwd = "password";
   immutable string constr = "host=localhost;user=user;pwd=password;db=mysqld";

   Connection c1 = new Connection();
   c1.open(host, user, pwd, "mysqld");
   assert(c1.serverOK);
   c1.close();

   c1 = new Connection();
   c1.open(constr);
   assert(c1.serverOK);
   c1.close();

// This is installation specific - alter as required
   c1 = new Connection(constr);
   assert(c1.serverOK());
   assert(c1.currentDB == "mysqld");
   assert(c1.clientVersion[0..4] == "5.5.");
   assert(c1.hostInfo == "Localhost via UNIX socket");
   assert(c1.serverVersion[0..4] == "5.1.");
   assert(c1.stats[0..8] == "Uptime: ");
   c1.reportTruncation(true);
}
/*
string[] GetDataBases()
string[] GetSchemas()
IColumns GetColumns()
string [] GetStoredPredures()
*/

/**
 * A struct to hold column metadata
 *
 */
struct MySQLColumn
{
   /// The database that the table having this column belongs to.
   string schema;
   /// The table that this column belongs to.
   string table;
   /// The name of the column.
   string name;
   /// Zero based index of the column within a table row.
   uint index;
   /// Is the default value NULL?
   bool defaultNull;
   /// The default value as a string if not NULL
   string defaultValue;
   /// Can the column value be set to NULL
   bool nullable;
   /// What type is the column - tinyint, char, varchar, blob, date etc
   string type;            // varchar tinyint etc
   /// Capacity in characters, -1L if not applicable
   long charsMax;
   /// Capacity in bytes - same as chars if not a unicode table definition, -1L if not applicable.
   long octetsMax;
   /// Presentation information for numerics, -1L if not applicable.
   short numericPrecision;
   /// Scale information for numerics or NULL, -1L if not applicable.
   short numericScale;
   /// Character set, "<NULL>" if not applicable.
   string charSet;
   /// Collation, "<NULL>" if not applicable.
   string collation;
   /// More detail about the column type, e.g. "int(10) unsigned".
   string colType;
   /// Information about the column's key status, blank if none.
   string key;
   /// Extra information.
   string extra;
   /// Privileges for logged in user.
   string privileges;
   /// Any comment that was set at table definition time.
   string comment;
}

/**
 * A struct to hold stored function metadata
 *
 */
struct MySQLProcedure
{
   string db;
   string name;
   string type;
   string definer;
   MYSQL_DATETIME modified;
   MYSQL_DATETIME created;
   string securityType;
   string comment;
   string charSetClient;
   string collationConnection;
   string collationDB;
}

/**
 * Facilities to recover meta-data from a connection
 *
 * It is important to bear in mind that the methods provided will only return the
 * information that is available to the connected user. This may well be quite limited.
 */
struct MetaData
{
private:
   Connection _con;
   MYSQL_RES* _pres;

   MySQLProcedure[] stored(bool procs)
   {
      string query = procs? "show procedure status where db='": "show function status where db='";
      query ~= _con.currentDB ~ "'";
      if (mysql_real_query(_con.CH, query.ptr, query.length))
         throw new MyX(_con.CH, __FILE__, __LINE__);
      _pres = mysql_store_result(_con.CH);
      if (_pres is null)
         throw new MyX(_con.CH, __FILE__, __LINE__);
      MySQLProcedure[] pa;
      uint n = cast(uint) _pres.row_count;
      pa.length = n;
      for (uint i = 0; i < n; i++)
      {
         MySQLProcedure foo;
         MYSQL_ROW r = mysql_fetch_row(_pres);
         for (int j = 0; j < 11; j++)
         {
            string t;
            bool isNull = (r[j] is null);
            if (!isNull)
               t = to!string(r[j]);
            switch (j)
            {
               case 0:
                  foo.db = t;
                  break;
               case 1:
                  foo.name = t;
                  break;
               case 2:
                  foo.type = t;
                  break;
               case 3:
                  foo.definer = t;
                  break;
               case 4:
                  foo.modified = cast(MYSQL_DATETIME) toMyTime(t, enum_field_types.MYSQL_TYPE_DATETIME);
                  break;
               case 5:
                  foo.created = cast(MYSQL_DATETIME) toMyTime(t, enum_field_types.MYSQL_TYPE_DATETIME);
                  break;
               case 6:
                  foo.securityType = t;
                  break;
               case 7:
                  foo.comment = t;
                  break;
               case 8:
                  foo.charSetClient = t;
                  break;
               case 9:
                  foo.collationConnection = t;
                  break;
               case 10:
                  foo.collationDB = t;
                  break;
               default:
                  break;
            }
         }
         pa[i] = foo;
      }
      return pa;
   }

public:
   this(Connection con)
   {
      _con = con;
   }

   /**
    * List the available databases
    *
    * Note that if you have connected using the credentials of a user with limited permissions
    * you may not get many results.
    *
    * Params:
    *    like = A simple wildcard expression with '%' or '_' terms for a limited selection, or null for all.
    */
   string[] databases(string like = null)
   {
      string[] rv;
      _pres = mysql_list_dbs(_con.CH, toStringz(like));
      if (_pres is null)
         throw new MyX(_con.CH, __FILE__, __LINE__);
      for (;;)
      {
         MYSQL_ROW r = mysql_fetch_row(_pres);
         if (r is null)
            break;
         rv ~= to!string(r[0]);
      }
      return rv;
   }

   /**
    * List the tables in the current database
    *
    * Params:
    *    like = A simple wildcard expression with '%' or '_' terms for a limited selection, or null for all.
    */
   string[] tables(string like = null)
   {
      string[] rv;
      _pres = mysql_list_tables(_con.CH, toStringz(like));
      if (_pres is null)
         throw new MyX(_con.CH, __FILE__, __LINE__);
      for (;;)
      {
         MYSQL_ROW r = mysql_fetch_row(_pres);
         if (r is null)
            break;
         rv ~= to!string(r[0]);
      }
      return rv;
   }

   /**
    * Get column metadata for a table in the current database
    *
    * Params:
    *    table = The table name
    * Returns:
    *    An array of MySQLColumn structs
    */
   MySQLColumn[] columns(string table)
   {
      string query = "select * from information_schema.COLUMNS where table_name='" ~ table ~ "'";
      if (mysql_real_query(_con.CH, query.ptr, query.length))
         throw new MyX(_con.CH, __FILE__, __LINE__);
      _pres = mysql_store_result(_con.CH);
      if (_pres is null)
         throw new MyX(_con.CH, __FILE__, __LINE__);
      MySQLColumn[] ca;
      uint n = cast(uint) _pres.row_count;
      ca.length = n;
      for (uint i = 0; i < n; i++)
      {
         MySQLColumn col;
         MYSQL_ROW r = mysql_fetch_row(_pres);
         for (int j = 1; j < 19; j++)
         {
            string t;
            bool isNull = (r[j] is null);
            if (!isNull)
               t = to!string(r[j]);
            switch (j)
            {
               case 1:
                  col.schema = t;
                  break;
               case 2:
                  col.table = t;
                  break;
               case 3:
                  col.name = t;
                  break;
               case 4:
                  col.index = to!uint(t)-1;
                  break;
               case 5:
                  if (isNull)
                     col.defaultNull = true;
                  else
                     col.defaultValue = t;
                  break;
               case 6:
                  if (t == "YES")
                     col.nullable = true;
                  break;
               case 7:
                  col.type = t;
                  break;
               case 8:
                  col.charsMax = isNull? -1L: cast(long) to!uint(t);
                  break;
               case 9:
                  col.octetsMax = isNull? -1L: cast(long) to!uint(t);
                  break;
               case 10:
                  col.numericPrecision = isNull? -1: to!short(t);
                  break;
               case 11:
                  col.numericScale = isNull? -1: to!short(t);
                  break;
               case 12:
                  col.charSet = isNull? "<NULL>": t;
                  break;
               case 13:
                  col.collation = isNull? "<NULL>": t;
                  break;
               case 14:
                  col.colType = t;
                  break;
               case 15:
                  col.key = t;
                  break;
               case 16:
                  col.extra = t;
                  break;
               case 17:
                  col.privileges = t;
                  break;
               case 18:
                  col.comment = t;
                  break;
               default:
                  break;
            }
         }
         ca[i] = col;
      }
      return ca;
   }

   /**
    * Get list of stored functions in the current database, and their properties
    *
    */
   MySQLProcedure[] functions()
   {
      return stored(false);
   }

   /**
    * Get list of stored procedures in the current database, and their properties
    *
    */
   MySQLProcedure[] procedures()
   {
      return stored(true);
   }
}

unittest
{
   immutable string constr = "host=localhost;user=user;pwd=password;db=mysqld";
   Connection con = new Connection(constr);
   MetaData md = MetaData(con);
   string[] dbList = md.databases();
   int count = 0;
   foreach (string db; dbList)
   {
      if (db == "mysqld" || db == "information_schema")
         count++;
   }
   assert(count == 2);
   dbList = md.databases("%_schema");
   assert(dbList.length == 1);
   string[] tList = md.tables();
   count = 0;
   foreach (string t; tList)
   {
      if (t == "basetest" || t == "tblob")
         count++;
   }
   assert(count == 2);

   MySQLColumn[] ca = md.columns("basetest");
   assert(ca[0].schema == "mysqld" && ca[0].table == "basetest" && ca[0].name == "boolcol" && ca[0].index == 0 &&
              ca[0].defaultNull && ca[0].nullable && ca[0].type == "bit" && ca[0].charsMax == -1 && ca[0].octetsMax == -1 &&
              ca[0].numericPrecision == 1 && ca[0].numericScale == -1 && ca[0].charSet == "<NULL>" && ca[0].collation == "<NULL>"  &&
              ca[0].colType == "bit(1)");
   assert(ca[1].schema == "mysqld" && ca[1].table == "basetest" && ca[1].name == "bytecol" && ca[1].index == 1 &&
              ca[1].defaultNull && ca[1].nullable && ca[1].type == "tinyint" && ca[1].charsMax == -1 && ca[1].octetsMax == -1 &&
              ca[1].numericPrecision == 3 && ca[1].numericScale == 0 && ca[1].charSet == "<NULL>" && ca[1].collation == "<NULL>"  &&
              ca[1].colType == "tinyint(4)");
   assert(ca[2].schema == "mysqld" && ca[2].table == "basetest" && ca[2].name == "ubytecol" && ca[2].index == 2 &&
              ca[2].defaultNull && ca[2].nullable && ca[2].type == "tinyint" && ca[2].charsMax == -1 && ca[2].octetsMax == -1 &&
              ca[2].numericPrecision == 3 && ca[2].numericScale == 0 && ca[2].charSet == "<NULL>" && ca[2].collation == "<NULL>"  &&
              ca[2].colType == "tinyint(3) unsigned");
   assert(ca[3].schema == "mysqld" && ca[3].table == "basetest" && ca[3].name == "shortcol" && ca[3].index == 3 &&
              ca[3].defaultNull && ca[3].nullable && ca[3].type == "smallint" && ca[3].charsMax == -1 && ca[3].octetsMax == -1 &&
              ca[3].numericPrecision == 5 && ca[3].numericScale == 0 && ca[3].charSet == "<NULL>" && ca[3].collation == "<NULL>"  &&
              ca[3].colType == "smallint(6)");
   assert(ca[4].schema == "mysqld" && ca[4].table == "basetest" && ca[4].name == "ushortcol" && ca[4].index == 4 &&
              ca[4].defaultNull && ca[4].nullable && ca[4].type == "smallint" && ca[4].charsMax == -1 && ca[4].octetsMax == -1 &&
              ca[4].numericPrecision == 5 && ca[4].numericScale == 0 && ca[4].charSet == "<NULL>" && ca[4].collation == "<NULL>"  &&
              ca[4].colType == "smallint(5) unsigned");
   assert(ca[5].schema == "mysqld" && ca[5].table == "basetest" && ca[5].name == "intcol" && ca[5].index == 5 &&
              ca[5].defaultNull && ca[5].nullable && ca[5].type == "int" && ca[5].charsMax == -1 && ca[5].octetsMax == -1 &&
              ca[5].numericPrecision == 10 && ca[5].numericScale == 0 && ca[5].charSet == "<NULL>" && ca[5].collation == "<NULL>"  &&
              ca[5].colType == "int(11)");
   assert(ca[6].schema == "mysqld" && ca[6].table == "basetest" && ca[6].name == "uintcol" && ca[6].index == 6 &&
              ca[6].defaultNull && ca[6].nullable && ca[6].type == "int" && ca[6].charsMax == -1 && ca[6].octetsMax == -1 &&
              ca[6].numericPrecision == 10 && ca[6].numericScale == 0 && ca[6].charSet == "<NULL>" && ca[6].collation == "<NULL>"  &&
              ca[6].colType == "int(10) unsigned");
   assert(ca[7].schema == "mysqld" && ca[7].table == "basetest" && ca[7].name == "longcol" && ca[7].index == 7 &&
              ca[7].defaultNull && ca[7].nullable && ca[7].type == "bigint" && ca[7].charsMax == -1 && ca[7].octetsMax == -1 &&
              ca[7].numericPrecision == 19 && ca[7].numericScale == 0 && ca[7].charSet == "<NULL>" && ca[7].collation == "<NULL>"  &&
              ca[7].colType == "bigint(20)");
   assert(ca[8].schema == "mysqld" && ca[8].table == "basetest" && ca[8].name == "ulongcol" && ca[8].index == 8 &&
              ca[8].defaultNull && ca[8].nullable && ca[8].type == "bigint" && ca[8].charsMax == -1 && ca[8].octetsMax == -1 &&
              ca[8].numericPrecision == 20 && ca[8].numericScale == 0 && ca[8].charSet == "<NULL>" && ca[8].collation == "<NULL>"  &&
              ca[8].colType == "bigint(20) unsigned");
   assert(ca[9].schema == "mysqld" && ca[9].table == "basetest" && ca[9].name == "charscol" && ca[9].index == 9 &&
              ca[9].defaultNull && ca[9].nullable && ca[9].type == "char" && ca[9].charsMax == 10 && ca[9].octetsMax == 10 &&
              ca[9].numericPrecision == -1 && ca[9].numericScale == -1 && ca[9].charSet == "latin1" && ca[9].collation == "latin1_swedish_ci"  &&
              ca[9].colType == "char(10)");
   assert(ca[10].schema == "mysqld" && ca[10].table == "basetest" && ca[10].name == "stringcol" && ca[10].index == 10 &&
              ca[10].defaultNull && ca[10].nullable && ca[10].type == "varchar" && ca[10].charsMax == 50 && ca[10].octetsMax == 50 &&
              ca[10].numericPrecision == -1 && ca[10].numericScale == -1 && ca[10].charSet == "latin1" && ca[10].collation == "latin1_swedish_ci"  &&
              ca[10].colType == "varchar(50)");
   assert(ca[11].schema == "mysqld" && ca[11].table == "basetest" && ca[11].name == "bytescol" && ca[11].index == 11 &&
              ca[11].defaultNull && ca[11].nullable && ca[11].type == "tinyblob" && ca[11].charsMax == 255 && ca[11].octetsMax == 255 &&
              ca[11].numericPrecision == -1 && ca[11].numericScale == -1 && ca[11].charSet == "<NULL>" && ca[11].collation == "<NULL>"  &&
              ca[11].colType == "tinyblob");
   assert(ca[12].schema == "mysqld" && ca[12].table == "basetest" && ca[12].name == "datecol" && ca[12].index == 12 &&
              ca[12].defaultNull && ca[12].nullable && ca[12].type == "date" && ca[12].charsMax == -1 && ca[12].octetsMax == -1 &&
              ca[12].numericPrecision == -1 && ca[12].numericScale == -1 && ca[12].charSet == "<NULL>" && ca[12].collation == "<NULL>"  &&
              ca[12].colType == "date");
   assert(ca[13].schema == "mysqld" && ca[13].table == "basetest" && ca[13].name == "timecol" && ca[13].index == 13 &&
              ca[13].defaultNull && ca[13].nullable && ca[13].type == "time" && ca[13].charsMax == -1 && ca[13].octetsMax == -1 &&
              ca[13].numericPrecision == -1 && ca[13].numericScale == -1 && ca[13].charSet == "<NULL>" && ca[13].collation == "<NULL>"  &&
              ca[13].colType == "time");
   assert(ca[14].schema == "mysqld" && ca[14].table == "basetest" && ca[14].name == "dtcol" && ca[14].index == 14 &&
              ca[14].defaultNull && ca[14].nullable && ca[14].type == "datetime" && ca[14].charsMax == -1 && ca[14].octetsMax == -1 &&
              ca[14].numericPrecision == -1 && ca[14].numericScale == -1 && ca[14].charSet == "<NULL>" && ca[14].collation == "<NULL>"  &&
              ca[14].colType == "datetime");
   assert(ca[15].schema == "mysqld" && ca[15].table == "basetest" && ca[15].name == "doublecol" && ca[15].index == 15 &&
              ca[15].defaultNull && ca[15].nullable && ca[15].type == "double" && ca[15].charsMax == -1 && ca[15].octetsMax == -1 &&
              ca[15].numericPrecision == 22 && ca[15].numericScale == -1 && ca[15].charSet == "<NULL>" && ca[15].collation == "<NULL>"  &&
              ca[15].colType == "double");
   assert(ca[16].schema == "mysqld" && ca[16].table == "basetest" && ca[16].name == "floatcol" && ca[16].index == 16 &&
              ca[16].defaultNull && ca[16].nullable && ca[16].type == "float" && ca[16].charsMax == -1 && ca[16].octetsMax == -1 &&
              ca[16].numericPrecision == 12 && ca[16].numericScale == -1 && ca[16].charSet == "<NULL>" && ca[16].collation == "<NULL>"  &&
              ca[16].colType == "float");
   assert(ca[17].schema == "mysqld" && ca[17].table == "basetest" && ca[17].name == "nullcol" && ca[17].index == 17 &&
              ca[17].defaultNull && ca[17].nullable && ca[17].type == "int" && ca[17].charsMax == -1 && ca[17].octetsMax == -1 &&
              ca[17].numericPrecision == 10 && ca[17].numericScale == 0 && ca[17].charSet == "<NULL>" && ca[17].collation == "<NULL>"  &&
              ca[17].colType == "int(11)");
   MySQLProcedure[] pa = md.functions();
   assert(pa[0].db == "mysqld" && pa[0].name == "hello" && pa[0].type == "FUNCTION");
   pa = md.procedures();
   assert(pa[0].db == "mysqld" && pa[0].name == "insert2" && pa[0].type == "PROCEDURE");
}


enum  // parameter direction
{
   ParamIn,
   ParamInOut,
   ParamOut
}

enum  // for disposition
{
   UNKNOWN,
   NON_QUERY,
   RESULT,
   RESULT_PENDING,
   RESULT_MISSING,
}

typedef void[] delegate(ref uint) InChunkDelegate;
typedef void delegate(ubyte*, uint, ulong) OutChunkDelegate;

/**
 * An extension to MYSQL_BIND
 *
 * The mySQL API deals with character/byte arrays using char*. Since D arrays are length/pointer beasts
 * extra binding information is required. MYSQL_BIND provides a convenient void* extension field.
 *
 * We point this at the BindExt struct, with fields:<ul>
 *    <li>pa - a pointer to the bound array, through which we can manipulate its length and rerieve its pointer.</li>
 *    <li>chunkBuffer - a ubyte[] that is used as an intermediate buffer when doing chunked transfers.</li>
 *    <li>inCD - a delegate used for IN transfers.</li>
 *    <li>outCD - a delegate used for out transfers.</li></ul>
 */
struct BindExt
{
   ubyte[]* pa;
   ubyte[] chunkBuffer;
   uint chunkSize;
   InChunkDelegate inCD;
   OutChunkDelegate outCD;
}

/**
 * A class to encapsulate struct mysql_real_query(), MYSQL_STMT, and their associated functions.
 *
 * Methods execXXX are provided to execute simple SQL queries/commands, to execute prepared statements, and to
 * create result set objects. There are also ancillary methods to create parameters for prepared statements, etc.
 *
 */
struct Command
{
private:
   Connection _con;
   MYSQL_STMT* _stmt;
   MYSQL_BIND[] _ibsa, _obsa;

   MYSQL_RES* _lastResult, _pmetaRes;
   bool _inChunked, _outChunked;
   uint _nip, _nop;
   string _sql;
   string _prevFunc;
   bool _prepared;
   bool _rowsAvailable;
   int _disposition;
   ulong _rows;
   int _fields;

   void bindParams()
   {
      if (mysql_stmt_bind_param(_stmt, _ibsa.ptr))
         throw new MyX(_stmt.mysql, __FILE__, __LINE__);
   }

   void bindResults()
   {
      for (int i = 0; i < _nop; i++)
      {
         MYSQL_BIND* bp = &_obsa[i];
         if (bp.extension is null)
            continue;
         BindExt* bx = cast(BindExt*) bp.extension;
         size_t ml = _stmt.fields[i].length;
         if (bx.chunkSize)
         {
            bx.chunkBuffer.length = bx.chunkSize;
            bp.buffer = bx.chunkBuffer.ptr;
            bp.buffer_length = bx.chunkSize;
         }
         else
         {
            (*bx.pa).length = ml;
            bp.buffer = (*bx.pa).ptr;
            bp.buffer_length = ml;
         }
      }
      if (mysql_stmt_bind_result(_stmt, _obsa.ptr))
         throw new MyX(_stmt.mysql, __FILE__, __LINE__);
   }

   /*
    * Appends a new parameter to the input parameter list.
    *
    * Note that the order in which parameters are added must correspond to the order of '?' place markers
    * within the sql.
    *
    * Returns:
    *   The appended parameter.
    */
   MYSQL_BIND* appendNewIP(out int index)
   {
      if (_nip >= _ibsa.length)
         _ibsa.length = _ibsa.length+10;
      index = _nip;
      MYSQL_BIND* p = &_ibsa[_nip++];
      return p;
   }

   /*
    * Appends a new parameter to the output parameter list.
    *
    * Note that the order in which parameters are added must correspond to the order of '?' place markers
    * within the sql.
    *
    * Returns:
    )   The appended parameter.
    */
   MYSQL_BIND* appendNewOP(out int index)
   {
      if (_nop >= _obsa.length)
         _obsa.length = _obsa.length+10;
      index = _nop;
      MYSQL_BIND* p = &_obsa[_nop++];
      return p;
   }

   void doChunkedInTransfer(int paramNum)
   {
      MYSQL_BIND* bs = &_ibsa[paramNum];
      BindExt* bx = cast(BindExt*) _ibsa[paramNum].extension;
      uint sent = 0;
      InChunkDelegate icd = bx.inCD;

      if (icd !is null)
      {
         uint ur;
         for (;;)
         {
            ur = bx.chunkSize;
            byte[] next = cast(byte[]) icd(ur);
            if (mysql_stmt_send_long_data(_stmt, paramNum, cast(char*) next.ptr, next.length))
            {
               const char* s = mysql_stmt_error(_stmt);
               throw new MyX(to!string(mysql_stmt_error(_stmt)), __FILE__, __LINE__);
            }
            if (ur < bx.chunkSize)
               break;
            sent += ur;
         }
      }
      else
      {
         for(;;)
         {
            uint send = (bs.buffer_length-sent > bx.chunkSize)? bx.chunkSize: bs.buffer_length-sent;
            if (mysql_stmt_send_long_data(_stmt, paramNum, (cast(char*) bs.buffer)+sent, send))
            {
               const char* s = mysql_stmt_error(_stmt);
               throw new MyX(s[0..strlen(s)].idup, __FILE__, __LINE__);
            }
            if (send < bx.chunkSize)
               break;
            sent += send;
            if (sent >= bs.buffer_length)
               break;
         }
      }
   }

public:

   /**
    * Constructor to produce a Command object with no SQL and preset length binding data arrays.
    *
    * Params:
    *   con = Reference to a Connection
    */
   this(Connection con)
   {
      _con = con;
      _ibsa.length = 10;
      _obsa.length = 10;
   }

   /**
    * Constructor to produce a Command object with a current SQL command string
    *
    * Params:
    *   con = Reference to a Connection.
    *   sql = A SQL string.
    */
   this (string constr, string sql)
   {
      Connection tc = new Connection(constr);
      this(tc);
      _sql = sql;
   }

   /**
    * Constructor to produce a one-off Command object with a current SQL command string
    *
    * This constructor obtains a Connection on-the-fly, so if you only have one database query to make
    * yu can do so with minimal code.
    *
    * Params:
    *   con = Reference to a Connection.
    *   sql = A SQL string.
    */
   this (Connection con, string sql)
   {
      this(con);
      _sql = sql;
   }

   /**
    * An int that describes the outcome of a command
    *
    */
   @property int disposition() { return _disposition; }
   /**
    * A uint that gives the number of columns in the result set of a prepared query.
    *
    */
   @property uint fields() { return _fields; }

   /**
    * Prepare a command.
    *
    * Prepare is optional. You only call it in cases where you are going to bind D variables as input sources
    * or output targets, and you want to check how many bindings are needed.
    *
    * If you don't call it, the execPrepared and execTuple etc methods requiring it will call it for you.
    *
    * Returns:
    *   The number of input parameters  - ? - that were found in the SQL
    */
   int prepare()
   {
      if (!_sql.length)
         throw new MyX("No SQL text has been specified for the Command", __FILE__, __LINE__);
      if (_lastResult !is null)
      {
         mysql_free_result(_lastResult);
         _lastResult = null;
      }
      if (_stmt !is null)     // ditch any existing prepared statement
      {
         if (mysql_stmt_close(_stmt))
            throw new MyX(_con.handle, __FILE__, __LINE__);
      }
      _stmt = mysql_stmt_init(_con.handle);
      if (_stmt is null)
         throw new MyX("Failed to create statement handle - out of memory", __FILE__, __LINE__);
      if (mysql_stmt_prepare(_stmt, cast(char*) _sql.ptr, _sql.length))
         throw new MyX(_con.handle, __FILE__, __LINE__);
      _prepared = true;
      return mysql_stmt_param_count(_stmt);
   }

   /**
    * Put the Command object back into an initial state, with no associated SQL.
    */
   void close()
   {
      reset();
      sql("");
   }

   /**
    * Escape a string to be composed into an SQL query.
    *
    * This needs to be used to launder any user entered string, and string literals used in your program
    * as components of a query string.
    *
    * Does transformations such as
    *
    * Params:
    *    orig = the unescaped string.
    * Returns:
    *   The sanitized string.
    */
    static string escapeString(Connection con, string orig)
    {
      char[] buf;
      buf.length = orig.length*2+1;
      ulong rv = mysql_real_escape_string(con.CH, buf.ptr, cast(const(char*)) orig.ptr, cast(ulong) orig.length);
      if (rv > size_t.max)
         throw new MyX("Escaped string is too long for this platform", __FILE__, __LINE__);
      size_t sz = cast(size_t) rv;
      return buf[0..sz].idup;
    }

   /**
    * Set the SQL for the Command object.
    *
    * Returns:
    *   The SQL string currently set for the Command.
    */
   @property string sql() { return _sql; }

   /**
    * Set the SQL for the Command object.
    *
    * Params:
    *   sql = An SQL string.
    *
    * Returns:
    *   The previously set string.
    */
   @property string sql(string s)
   {
      string old = _sql;
      reset();
      _sql = s;
      return old;
   }

   /**
    * Gets a reference to the connection that was used to create this Command.
    */
   Connection connection() { return _con; }

   /**
    * Attempt to cancel an ongoing command
    */
   void cancel()
   {
      if (mysql_stmt_close(_stmt))
         throw new MyX(_con.handle, __FILE__, __LINE__);
      _prepared = false;
   }

   void setStmtDone()
   {
      if (_stmt !is null)
         _stmt.state = enum_mysql_stmt_state.MYSQL_STMT_EXECUTE_DONE;
   }

   /**
    * Put the Command object back into the state before prepare() and execXXX().
    *
    * The current SQL is retained.
    */
   void reset()
   {
      if (_lastResult !is null)
      {
         mysql_free_result(_lastResult);
         _lastResult = null;
      }
      if (_stmt !is null)
      {
         mysql_stmt_close(_stmt);
         _stmt = null;
      }
      for (int i = 0; i < _nip; i++)
      {
         _ibsa[i] = MYSQL_BIND.init;
      }
      for (int i = 0; i < _nop; i++)
      {
         _obsa[i] = MYSQL_BIND.init;
      }

      _nip = 0;
      _nop = 0;
      _prepared = _inChunked = _outChunked = false;
      _rowsAvailable = false;
   }

   /**
    * Clears the arrays of parameters/bind structs created for this object.
    */
   void clearParams()
   {
      _nip = 0;
      _nop = 0;
      _prepared = false;
   }

   /**
    * Create a parameter - in, inout, or out, and possibly 'chunked'.
    *
    * The new parameter is appended to the appropriate array of binding parameters (in or out or both)
    * associated with the Command object.
    *
    * If you have a bunch of similar parameters to set up that are all of the same kind, e.g. all IN,
    * and none chunked, or all OUT and not chunked, you can use setInBindings(). As long as you use
    * the correct sequence, you can mix the two approaches.
    * Example:
    *    setInBindings(a, b, c);<br>
    *    createParam(d, ParamIn, 65535);<br>
    *    setInBindings(e, f, g);<br>
    *
    * Params:
    *    T = The type for the parameter.
    *    target = A value of that type from which input will be taken or into which output will be placed.
    *    direction = ParamIn, ParamInOut, or ParamOut - defaults to ParamIn
    *    inChunkSize = Size of chunks for IN transfer.
    *    outChunkSize = Size of chunks for OUT chunked transfer.
    *    inCD = delegate for IN transfer.
    *    outCD = delegate for OUT transfer.
    *
    */
   void createParam(T)(ref T target, int direction = ParamIn, uint inChunkSize = 0, uint outChunkSize = 0,
                                       InChunkDelegate inCD = null, OutChunkDelegate outCD= null)
   {
      MYSQL_BIND* bsin;
      MYSQL_BIND* bsout;
      int index;

      if (inChunkSize)
         _inChunked = true;
      if (outChunkSize)
         _outChunked = true;

      if (direction == ParamOut)
      {
         bsout = appendNewOP(index);
         bsout.buffer = &target;
         bsout.buffer_length = T.sizeof;
         bsout.is_null = &bsout.is_null_value;
      }
      else if (direction == ParamInOut)
      {
         bsin = appendNewIP(index);
         bsin.buffer = &target;
         bsin.buffer_length = T.sizeof;
         bsin.is_null = &bsin.is_null_value;

         bsout = appendNewOP(index);
         bsout.buffer = &target;
         bsout.buffer_length = T.sizeof;
         bsout.is_null = &bsout.is_null_value;
      }
      else
      {
         bsin = appendNewIP(index);
         bsin.buffer = &target;
         bsin.buffer_length = T.sizeof;
         bsin.is_null = &bsin.is_null_value;
      }

      enum_field_types ft;
      static if (is(T : bool))
      {
         ft = enum_field_types.MYSQL_TYPE_BIT;
      }
      else static if (is(T : ulong))         // an integral type
      {
         bool uns = (T.min == 0);
         switch(T.sizeof)
         {
            case byte.sizeof:
               ft = enum_field_types.MYSQL_TYPE_TINY;
               break;
            case short.sizeof:
               ft = enum_field_types.MYSQL_TYPE_SHORT;
               break;
            case int.sizeof:
               ft = enum_field_types.MYSQL_TYPE_LONG;
               break;
            case long.sizeof:
               ft = enum_field_types.MYSQL_TYPE_LONGLONG;
               break;
            default:
               break;
         }
         if (bsin !is null) bsin.is_unsigned = uns? 1: 0;
         if (bsout !is null) bsout.is_unsigned = uns? 1: 0;
      }
      else static if (is(T : double))   // floating point
      {
         if (is(T == float))
            ft = enum_field_types.MYSQL_TYPE_FLOAT;
         else
            ft = enum_field_types.MYSQL_TYPE_DOUBLE;
      }
      else static if (is(T == string) || is(T == char[]) || is(T == ubyte[]) || is(T == byte[])) // byte array of some kind
      {
         if (is(typeof(target) == string) && direction != ParamIn)
            throw new MyX("Target is immutable", __FILE__, __LINE__);
         if (is(T == char[]))
            ft = enum_field_types.MYSQL_TYPE_VAR_STRING;
         else
            ft = enum_field_types.MYSQL_TYPE_BLOB;

         BindExt* bx = new BindExt();
         if (direction == ParamIn)
         {
            bsin.extension = bx;
            bx.pa = cast(ubyte[]*) &target;
            bx.chunkSize = inChunkSize;
            bx.inCD = inCD;
            bsin.buffer = cast(void*) target.ptr;
            bsin.buffer_length = target.length;
            bsin.length = &bsin.buffer_length;
         }
         else if (direction == ParamInOut)
         {
            bsin.extension = bx;
            bx.pa = cast(ubyte[]*) &target;
            bx.chunkSize = inChunkSize;
            bx.inCD = inCD;
            bsin.buffer = cast(void*) target.ptr;
            bsin.buffer_length = target.length;
            bsin.length = &bsin.buffer_length;

            bx = new BindExt();
            bsout.extension = bx;
            bx.pa = cast(ubyte[]*) &target;
            bx.chunkSize = outChunkSize;
            bx.outCD = outCD;
            if (bx.chunkSize)
            {
               bx.chunkBuffer.length = target.length;
               bsout.buffer = bx.chunkBuffer.ptr;
            }
            else
               bsout.buffer = cast(void*) target.ptr;
            bsout.buffer_length = target.length;
            // The latter will be tweaked at bind time to suit the max length of the field
            bsout.length = &bsout.length_value;
         }
         else
         {
            bsout.extension = bx;
            bx.pa = cast(ubyte[]*) &target;
            bx.chunkSize = outChunkSize;
            bx.outCD = outCD;
            if (bx.chunkSize)
            {
               bx.chunkBuffer.length = target.length;
               bsout.buffer = bx.chunkBuffer.ptr;
            }
            else
               bsout.buffer = cast(void*) target.ptr;
            bsout.buffer_length = target.length;
            bsout.length = &bsout.length_value;
         }
      }
      else static if (is(T == MYSQL_TIMEDIFF))
         ft = enum_field_types.MYSQL_TYPE_TIME;
      else static if (is(T == MYSQL_DATE))
         ft = enum_field_types.MYSQL_TYPE_DATE;
      else static if (is(T == MYSQL_DATETIME))
         ft = enum_field_types.MYSQL_TYPE_DATETIME;
      else static if (is(T == MYSQL_TIMESTAMP))
         ft = enum_field_types.MYSQL_TYPE_TIMESTAMP;
      else
          throw new MyX("Unsupported type passed to createParam() - " ~ T.stringof, __FILE__, __LINE__);
      if (bsin !is null) bsin.buffer_type = ft;
      if (bsout !is null) bsout.buffer_type = ft;
   }


   /**
    * Create a parameter linked to a Variant - in, inout, or out, and possibly 'chunked'.
    *
    * The new parameter is appended to the appropriate array of binding parameters (in or out or both)
    * associated with the Command object.
    *
    * Params:
    *    ref target = The MyVariant from which input will be taken or into which output will be placed.
    *    direction = ParamIn, ParamInOut, or ParamOut - defaults to ParamIn
    *    inChunkSize = Size of chunks for IN transfer.
    *    outChunkSize = Size of chunks for OUT chunked transfer.
    *    inCD = delegate for IN transfer.
    *    outCD = delegate for OUT transfer.
    */
   void createVariantParam(ref MyVariant target, int direction = ParamIn, uint inChunkSize = 0, uint outChunkSize = 0,
                                       InChunkDelegate inCD = null, OutChunkDelegate outCD= null)
   {
      MYSQL_BIND* bsin;
      MYSQL_BIND* bsout;

      if (inChunkSize)
         _inChunked = true;
      if (outChunkSize)
         _outChunked = true;

      int index;
      enum_field_types ft;
      string tname = target.type.toString();
      bool uns = false;
      void* pa;
      void* pb;
      switch (tname)
      {
         case "bool":
            ft = enum_field_types.MYSQL_TYPE_BIT;
            pb = target.peek!(bool);
            break;
         case "char":
            ft = enum_field_types.MYSQL_TYPE_STRING;
            pb = target.peek!(char);
            break;
         case "byte":
            ft = enum_field_types.MYSQL_TYPE_TINY;
            pb = target.peek!(byte);
            break;
         case "ubyte":
            ft = enum_field_types.MYSQL_TYPE_TINY;
            uns = true;
            pb = target.peek!(ubyte);
            break;
         case "short":
            ft = enum_field_types.MYSQL_TYPE_SHORT;
            pb = target.peek!(short);
            break;
         case "ushort":
            ft = enum_field_types.MYSQL_TYPE_SHORT;
            uns = true;
            pb = target.peek!(ushort);
            break;
         case "int":
            ft = enum_field_types.MYSQL_TYPE_LONG;
            pb = target.peek!(int);
            break;
         case "uint":
            ft = enum_field_types.MYSQL_TYPE_LONG;
            uns = true;
            pb = target.peek!(uint);
            break;
         case "long":
            ft = enum_field_types.MYSQL_TYPE_LONGLONG;
            pb = target.peek!(long);
            break;
         case "ulong":
            ft = enum_field_types.MYSQL_TYPE_LONGLONG;
            uns = true;
            break;
         case "immutable(char)[]":
            if (direction == ParamOut)
               throw new MyX("createVariantParam - out target is immutable", __FILE__, __LINE__);
            ft = enum_field_types.MYSQL_TYPE_VAR_STRING;
            pa = target.peek!(immutable(char)[]);
            break;
         case "char[]":
            ft = enum_field_types.MYSQL_TYPE_VAR_STRING;
            pa = target.peek!(char[]);
            break;
         case "byte[]":
            ft = enum_field_types.MYSQL_TYPE_BLOB;
            pa = target.peek!(byte[]);
            break;
         case "ubyte[]":
            ft = enum_field_types.MYSQL_TYPE_BLOB;
            pa = target.peek!(ubyte[]);
            break;
         case "float":
            ft = enum_field_types.MYSQL_TYPE_FLOAT;
            pb = target.peek!(float);
            break;
         case "double":
            ft = enum_field_types.MYSQL_TYPE_DOUBLE;
            pb = target.peek!(double);
            break;
         case "mysql.MYSQL_DATE":
            ft = enum_field_types.MYSQL_TYPE_DATE;
            pb = target.peek!(MYSQL_DATE);
            break;
         case "mysql.MYSQL_DATETIME":
            ft = enum_field_types.MYSQL_TYPE_DATETIME;
            pb = target.peek!(MYSQL_DATETIME);
            break;
         case "mysql.MYSQL_TIMESTAMP":
            ft = enum_field_types.MYSQL_TYPE_TIMESTAMP;
            pb = target.peek!(MYSQL_TIMESTAMP);
            break;
         case "mysql.MYSQL_TIMEDIFF":
            ft = enum_field_types.MYSQL_TYPE_TIME;
            pb = target.peek!(MYSQL_TIMEDIFF);
            break;
         default:
            throw new MyX("Unsupported type passed to createVariantParam() - " ~ target.type.toString(), __FILE__, __LINE__);
            break;
      }
      if (ft == enum_field_types.MYSQL_TYPE_VAR_STRING || ft == enum_field_types.MYSQL_TYPE_BLOB)
      {
         BindExt* bx = new BindExt();
         if (direction == ParamIn)
         {
            bsin = appendNewIP(index);
            bsin.extension = bx;
            bx.pa = cast(ubyte[]*) pa;
            bx.chunkSize = inChunkSize;
            bx.inCD = inCD;
            bsin.buffer = (*bx.pa).ptr;
            bsin.buffer_length = (*bx.pa).length;
            bsin.length = &bsin.buffer_length;
            bsin.is_null = &bsin.is_null_value;
         }
         else if (direction == ParamInOut)
         {
            bsin = appendNewIP(index);
            bsin.extension = bx;
            bx.pa = cast(ubyte[]*) pa;
            bx.chunkSize = inChunkSize;
            bx.inCD = inCD;
            bsin.buffer = (*bx.pa).ptr;
            bsin.buffer_length = (*bx.pa).length;
            bsin.length = &bsin.buffer_length;
            bsin.is_null = &bsin.is_null_value;

            bsout = appendNewOP(index);
            bx = new BindExt();
            bsout.extension = bx;
            bx.pa = cast(ubyte[]*) pa;
            bx.chunkSize = outChunkSize;
            bx.outCD = outCD;
            if (bx.chunkSize)
            {
               bx.chunkBuffer.length = (*bx.pa).length;
               bsout.buffer = bx.chunkBuffer.ptr;
            }
            else
               bsout.buffer = (*bx.pa).ptr;
            bsout.buffer_length = (*bx.pa).length;
            // The latter will be tweaked at bind time to suit the max length of the field
            bsout.length = &bsout.length_value;
            bsin.is_null = &bsin.is_null_value;
         }
         else
         {
            bsout = appendNewOP(index);
            bsout.extension = bx;
            bx.pa = cast(ubyte[]*) pa;
            bx.chunkSize = outChunkSize;
            bx.outCD = outCD;
            if (bx.chunkSize)
            {
               bx.chunkBuffer.length = (*bx.pa).length;
               bsout.buffer = bx.chunkBuffer.ptr;
            }
            else
               bsout.buffer = (*bx.pa).ptr;
            bsout.buffer_length = (*bx.pa).length;
            bsout.length = &bsout.length_value;
            bsout.is_null = &bsout.is_null_value;
        }
      }
      else
      {
         if (direction == ParamOut)
         {
            bsout = appendNewOP(index);
            bsout.buffer = pb;
            bsout.buffer_length = target.type.tsize;
            bsout.is_null = &bsout.is_null_value;
         }
         else if (direction == ParamInOut)
         {
            bsin = appendNewIP(index);
            bsin.buffer = pb;
            bsin.buffer_length = target.type.tsize;
            bsin.is_null = &bsin.is_null_value;

            bsout = appendNewOP(index);
            bsout.buffer = pb;
            bsout.buffer_length = target.type.tsize;
            bsout.is_null = &bsout.is_null_value;
         }
         else
         {
            bsin = appendNewIP(index);
            bsin.buffer = pb;
            bsin.buffer_length = target.type.tsize;
            bsin.is_null = &bsin.is_null_value;
         }
      }
      if (bsin !is null)
      {
         bsin.buffer_type = ft;
         bsin.is_unsigned = uns? 1: 0;
      }
      if (bsout !is null)
      {
         bsout.buffer_type = ft;
         bsout.is_unsigned = uns? 1: 0;
      }
   }

   /**
    * Update an input parameter prior to a further execution of execPrepared()
    *
    * This method is required because the in bind properties of string or byte[] parameters
    * need to be adjusted to take into account of the length of the new value and the fact that its
    * pointer will likely have changed.
    *
    * It's effect is equivalent to a simple assignment of a new value in the case of non-array variables.
    *
    * You can do a bunch of matching parameters together using updateInBindings().
    *
    * There is a caveat. You can't do this trick with a chunked input parameter that is tied to a delegate to
    * source the data, but you don't need to.
    *
    * Params:
    *   T = the variable type.
    *   target = The variable that will source the data for the parameter.
    *   newValue = Its new value.
    */
   void updateIP(T)(ref T target, T newValue)
   {
      target = newValue;
      updateIP(target);
   }

   /**
    * Update an input parameter prior to a further execution of execPrepared()
    *
    * This method is required because the in bind properties of string or byte[] parameters
    * need to be adjusted to take into account of the length of the new value and the fact that its
    * pointer will likely have changed.
    *
    * Use this overload when you have assigned the value yourself, or when some function has
    * modified target,
    *
    * You can do a bunch of matching parameters together using updateInBindings().
    *
    * There is a caveat. You can't do this trick with a chunked input parameter that is tied to a delegate to
    * source the data, but you don't need to.
    *
    * Params:
    *   T = the variable type.
    *   target = the variable that will source the data for the parameter.
    */
   void updateIP(T)(ref T target)
   {
      static if (is(T == string) || is(T == byte[]) || is(T == ubyte[]) || is(T == char[]))
      {
         // byte array of some kind
         MYSQL_BIND* bs;
         void* compare = &target;
         bool found = false;
         for (int i = 0; i < _nip; i++)
         {
            bs = &_ibsa[i];
            BindExt* bx = cast(BindExt*) bs.extension;
            if (bx is null)
               continue;
            if (compare == bx.pa)
            {
               found = true;
               break;
            }
         }
         if (!found)
            throw new MyX("updateIP - the original target was not found", __FILE__, __LINE__);
         bs.buffer = cast(void*) target.ptr;
         bs.buffer_length = target.length;
      }
   }

   /**
    * Create plain (no chunking) IN binding parameters for a bunch of Variants in an array.
    *
    * Params:
    *    va = Array of MyVariant.
    */
   void bindInArray(ref MyVariant[] va)
   {
      foreach (i, dummy; va)
      {
         createVariantParam(va[i]);
      }
   }

   /**
    * Create plain (no chunking) OUT binding parameters for a bunch of Variants in an array.
    *
    * Params:
    *    va = Array of MyVariant.
    */
   void bindOutArray(ref MyVariant[] va)
   {
      foreach (i, dummy; va)
      {
         createVariantParam(va[i], ParamOut);
      }
   }

   /**
    * Create plain (no chunking) IN binding parameters for the fields of a struct.
    *
    * Params:
    *    S = The struct type to be handled.
    *    s = Instance of S
    */
   void bindInStruct(S)(ref S s) if (is(S== struct))
   {
      foreach (i, dummy; s.tupleof)
      {
         createParam(s.tupleof[i]);
      }
   }

   /**
    * Create plain (no chunking) OUT binding parameters for the fields of a struct.
    *
    * Params:
    *    S = The struct type to be handled.
    *    s = Instance of S
    */
   void bindOutStruct(S)(ref S s) if (is(S== struct))
   {
      foreach (i, dummy; s.tupleof)
      {
         createParam(s.tupleof[i], ParamOut);
      }
   }

   /**
    * Create plain (no chunking) IN binding parameters from a tuple of variables.
    *
    * Params:
    *    T... = type tuple.
    *    args = List of variables
    */
   void setInBindings(T...)(ref T args)
   {
      foreach (int i, arg; args)
         createParam(args[i]);
   }

   /**
    * Create plain (no chunking) OUT binding parameters from a tuple of variables.
    *
    * Params:
    *    T... = type tuple.
    *    args = List of variables
    */
   void setOutBindings(T...)(ref T args)
   {
      foreach (int i, arg; args)
         createParam(args[i], ParamOut);
   }

   /**
    * Update a set of IN binding parameters from a tuple of variables.
    *
    * To use this, the variables must already have had new values assigned.

    * Params:
    *    T... = type tuple.
    *    args = List of variables
    */
   void updateInBindings(T...)(ref T args)
   {
      foreach (int i, arg; args)
         updateIP(args[i]);
   }

   /**
    * Execute a plain SQL command.
    *
    * You can use this method to execute any SQL statement.
    *
    * The method will provide information about the outcome in addition to the return value. If it was a non-query -
    * something like INSERT, DELETE, or UPDATE, the return value will be NON_QUERY, and the out parameter value
    * should be the number of rows affected.
    *
    * If the statement was something such as a SELECT, with a potential (though possibly empty) result set, then
    * disposition will be set to RESULT, in which case the getResultSet() method will give you access to it, and
    * the Command object's fields property will be set to the number of columns in the result set. The out
    * parameter ra will be set to zero in this case.
    *
    * If this method generates a result set, and you subsequently call another execXXX method, the result
    * will be wasted.
    *
    * Returns: The result disposition.
    *
    * Params:
    *   ra = out - the number of rows affected or in the result set.
    */
   int execSQL(out ulong ra)
   {
      _disposition = _fields = 0;
      if (_lastResult !is null)
         mysql_free_result(_lastResult);
      _lastResult = null;
      if (!_sql.length)
         throw new MyX("No SQL text has been specified for the Command", __FILE__, __LINE__);
      if (mysql_real_query(_con.handle, cast(char*) _sql.ptr, _sql.length))
         throw new MyX(_con.handle, __FILE__, __LINE__);
      _fields = mysql_field_count(_con.handle);
      if (_fields == 0)
      {
         // query does not return data - not a SELECT etc
         _disposition = NON_QUERY;
         ra = mysql_affected_rows(_con.handle);
      }
      else
      {
         _disposition = RESULT;
         ra = 0;
      }
      return _disposition;
   }

   /**
    * Execute a prepared command.
    *
    * With MySQL, Almost any SQL statement can be prepared, with input/output parameters either represented
    * by '?' in the SQL statement, or implicit, as in the case where there is a result set. For example:
    *
    * select col1, col2 from sometable where col3=?
    *
    * Could require two OUT parameters to receive the results from col1 and col2, and one in parameter to provide
    * the condition. However mysqld splits the cases where there would be a result set, so only IN parameters
    * are considered here. Further work will be required when stored procedures can have IN and OUT parameters.
    *
    * If you have ? placemarkers, you must bind them to variables in your program using the setInBindings() and/or
    * individually via the createParam() method etc.
    *
    * You may call prepare() explicitly so that you can check the number of parameters required for the statement. If
    * you don't, execPrepared will call it for you, and will throw if the number of parameters in the SQL and the
    * number of parameters actually created don't match.
    *
    * If you have not bound any input or output parameters then you could just use execSQL for things like INSERT,
    * UPDATE, and DELETE, and unless you plan to use the same statement many times in a session, this may be
    * more efficient.
    *
    * Params:
    *    ra = out - the number of rows affected or zero if there is a result set.
    * Returns:
    *    The number of columns in the result set if there were results
    */
   int execPrepared(out ulong ra)
   {
      _fields = 0;
      _rowsAvailable = false;
      int rv = 0;

      if (!_prepared)
         prepare();
      uint pc = mysql_stmt_param_count(_stmt);
      if (_nip < pc)
         throw new MyX("The SQL supplied for the command has placeholders - '?', but insufficient input parameters were created",
                                 __FILE__, __LINE__);
      _fields = mysql_stmt_field_count(_stmt);
      if (_nip)
         bindParams();
      for (int i = 0; i < _nip; i++)
      {
         BindExt* bx = cast(BindExt*) _ibsa[i].extension;
         if (bx is null)
            continue;
         if (bx.chunkSize)
            doChunkedInTransfer(i);
      }
      if (mysql_stmt_execute(_stmt))
         throw new MyX(_con.handle, __FILE__, __LINE__);
      if (!_fields)
         ra = mysql_stmt_affected_rows(_stmt);
      return _fields;
   }

   /**
    * Get a ResultSet object corresponding to the result set of a previous execSQL().
    *
    * This method gives access to the results of a SELECT or some other SQL statement that generated a result
    * set via execSQL(). You should probably have used used execSQLResult() or execPreparedResult() in the first place for
    * such cases.
    *
    * A ResultSet buffers all the rows to the client.
    *
    * Returns: A ResultSet object for the relevant result set.
    */
   ResultSet getResultSet()
   {
      if (_disposition != RESULT)
            throw new MyX("getResultSet called when there was no appropriate prior result", __FILE__, __LINE__);
      if (_lastResult !is null)
         mysql_free_result(_lastResult);
      _lastResult = mysql_store_result(_con.handle);
      ResultSet resultSet = new ResultSet(_lastResult);
      return resultSet;
   }

   /**
    * Get a ResultSequence object corresponding to the result set of a previous execSQL.
    *
    * This method gives access to the results of a SELECT or some other SQL statement that generates a result
    * set via execSQL(). You should probably have used used execResult() or execSequence() in the first place for
    * such cases.
    *
    * A ResultSequence does not buffer rows to the client - they must be fetched individually.
    *
    * Returns: A ResultSequence object for the relevant result set.
    */
   ResultSequence getResultSequence()
   {
      if (_disposition != RESULT)
            throw new MyX("getResultSequence called when there was no appropriate prior result", __FILE__, __LINE__);
      if (_lastResult !is null)
         mysql_free_result(_lastResult);
      _lastResult = mysql_use_result(_con.handle);
      ResultSequence resultSequence = new ResultSequence(_lastResult);
      return resultSequence;
   }

   /**
    * Get a ResultSet by directly executing an SQL command that is expected to produce one.
    *
    * This method is to be used for ad-hoc SELECTs and other queries that return a result set. The returned ResultSet
    * can be used as a random access Range to iterate through the resulting rows and access column data.
    * The entire result set is buffered to the client.
    *
    * This method throws if there is no result set.
    *
    * Returns: A ResultSet object.
    */
   ResultSet execSQLResult()
   {
      _disposition = _fields = 0;
      if (_lastResult !is null)
         mysql_free_result(_lastResult);
      _lastResult = null;
      if (!_sql.length)
         throw new MyX("No SQL text has been specified for the Command", __FILE__, __LINE__);
      if (mysql_real_query(_con.handle, cast(char*) _sql.ptr, _sql.length))
         throw new MyX(_con.handle, __FILE__, __LINE__);
      MYSQL_RES* res = mysql_store_result(_con.handle);
      if (res.field_count == 0)
         throw new MyX("The executed SQL did not produce a result set.", __FILE__, __LINE__);
      _fields = res.field_count;
      _rows = res.row_count;
      _disposition = RESULT;
      return new ResultSet(res);
   }

   /**
    * Get a ResultSet by executing a prepared SQL command that is expected to produce one.
    *
    * This method takes the statement data from a call to execPrepared, and if that has a result set, returns
    * a ResultSet object that can be used as a random access Range to iterate through the resulting rows
    * and access column data.
    *
    * The entire result set is buffered to the client. This method throws if there is no result set.
    *
    * Params:
    *    csa = an array indicating any columns that need to be transferred in chunks.
    *
    * Returns: A ResultSet object.
    */
   ResultSet execPreparedResult(ChunkingSpec[] csa = null)
   {
      ulong ra;
      int fc = execPrepared(ra);
      if (!fc)
         throw new MyX("The executed SQL did not produce a result set.", __FILE__, __LINE__);
      return new ResultSet(_stmt, csa);
   }

   /**
    * Performs a query, and returns a ResultSequence object.
    *
    * This method is to be used for ad-hoc SELECTs and other queries that return a result set. The returned
    * ResultSequence can be used as an Input Range to iterate through the resulting rows one at a time.
    * The result set is not buffered to the client.
    *
    * Returns: A ResultSequence object.
    */
   ResultSequence execSQLSequence()
   {
      _disposition = _fields = 0;
      if (_lastResult !is null)
         mysql_free_result(_lastResult);
      _lastResult = null;
      if (!_sql.length)
         throw new MyX("No SQL text has been specified for the Command", __FILE__, __LINE__);
      if (mysql_real_query(_con.handle, cast(char*) _sql.ptr, _sql.length))
         throw new MyX(_con.handle, __FILE__, __LINE__);
      MYSQL_RES* res = mysql_use_result(_con.handle);
      if (res.field_count == 0)
         throw new MyX("The specified query did not return a result set.", __FILE__, __LINE__);
      _fields = res.field_count;
      _rows = res.row_count;
      _disposition = RESULT_PENDING;
      return new ResultSequence(res);
   }

   /**
    * Get a ResultSequence by executing a prepared SQL command that is expected to produce a result set.
    *
    * This method takes the statement data from a call to execPrepared, and if that has a result set, returns
    * a ResultSequence object that can be used as an Input Range to iterate through the resulting rows
    * and access column data.
    *
    * The result set is not buffered to the client.
    *
    * Params:
    *    csa = an array indicating any columns that need to be transferred in chunks.
    *
    * Returns: A ResultSequence object.
    */
   ResultSequence execPreparedSequence(ChunkingSpec[] csa = null)
   {
      ulong ra;
      if (_stmt !is null)
         mysql_stmt_close(_stmt);
      int fc = execPrepared(ra);
      if (!fc)
         throw new MyX("The executed SQL did not produce a result set.", __FILE__, __LINE__);
      return new ResultSequence(_stmt, csa);
   }

   /**
    * Perform a query, and populate the value of a single column value into a D variable.
    *
    * If the query does not produce a result set, or produces a result set that has more than one column then
    * execScalar will throw. If it produces a result set with multiple rows, only the first row will be considered.
    * If it is not possible to convert the column value to type T, then execScalar will throw.
    *
    * The column value is automatically placed in the supplied variable. If it was NULL target will be unchanged.
    *
    * This is effectively obsoleted by execTuple(), and will likely be removed.
    *
    * Params:
    *   T = A variable type.
    *   target = An instance of that type, if it is a string type, the length should be set to what can be accepted.
    *
    * Returns: True if the result was a non-null value.
    */
   bool execScalar(T)(ref T target)
   {
      if (_prepared)
         throw new MyX("You must not prepare the statement before calling execScalar", __FILE__, __LINE__);
      prepare();
      uint fc = mysql_stmt_field_count(_stmt);
      if (fc != 1)
         throw new MyX("The statement would generate a result set that would not have exactly one column",
                        __FILE__, __LINE__);
      uint pc = mysql_stmt_param_count(_stmt);
      if (_nip < pc)
         throw new MyX("The SQL supplied for the command has placeholders - '?', but insufficient input parameters were created",
                                 __FILE__, __LINE__);
      if (_inChunked)
         throw new MyX("An input parameter was chunked, but execScalar does not support chunked in parameters.",
                                 __FILE__, __LINE__);
      createParam(target, ParamOut);
      if (_nip)
         bindParams();
      if (mysql_stmt_execute(_stmt))
         throw new MyX(_con.handle, __FILE__, __LINE__);

      bindResults();
      int fr = mysql_stmt_fetch(_stmt);
      if (fr == 1)
         throw new MyX(to!string(mysql_stmt_error(_stmt)), __FILE__, __LINE__);
      if (fr == MYSQL_NO_DATA)
         throw new MyX("No rows in result set", __FILE__, __LINE__);

      MYSQL_BIND* bs = &_obsa[0];
      bool rv = !bs.is_null_value;
      if (bs.extension !is null)
      {
         BindExt* bx = cast(BindExt*) bs.extension;
         (*bx.pa).length = bs.length_value;
      }
      // In case there were more rows -
      mysql_stmt_reset(_stmt);
      return rv;
   }

   /**
    * Perform a query, and populate values for a single resulting row into a tuple of D variables.
    *
    * If the query does not produce a result set, or produces one that has a number
    * of columns that does not match the tuple, then execTuple will throw. If it produces a result set with
    * multiple rows, only the first row will be considered.
    *
    * If it is not possible to convert the column value to the type of the tuple element, then execTuple will throw.
    *
    * OUT bindings are created automatically, and the results will appear in the variables of the tuple.
    *
    * Params:
    *   T = A type tuple (normally this will be infered.)
    *   args = A list of variables. If any are strings or byte arrays, the length must be set to what can be accepted.
    *
    * Returns: An array of bool indicating the values that were not NULL.
    */
   bool[] execTuple(T...)(ref T args)
   {
      if (_prepared)
         throw new MyX("You must not prepare the statement before calling execScalar", __FILE__, __LINE__);
      prepare();
      uint fc = mysql_stmt_field_count(_stmt);
      if (fc != args.length)
         throw new MyX("The statement would generate a result with the number of columns not equal to the number of arguments supplied",
                        __FILE__, __LINE__);
      uint pc = mysql_stmt_param_count(_stmt);
      if (_nip < pc)
         throw new MyX("The SQL supplied for the command has placeholders - '?', but insufficient input parameters were created",
                                 __FILE__, __LINE__);
      if (_inChunked)
         throw new MyX("An input parameter was chunked, but execTuple does not support chunked in parameters.",
                                 __FILE__, __LINE__);
      foreach (int i, arg; args)
         createParam(args[i], ParamOut);
      if (_nip)
         bindParams();
      if (mysql_stmt_execute(_stmt))
         throw new MyX(_con.handle, __FILE__, __LINE__);

      bindResults();
      int fr = mysql_stmt_fetch(_stmt);
      if (fr == 1)
         throw new MyX(to!string(mysql_stmt_error(_stmt)), __FILE__, __LINE__);
      if (fr == MYSQL_NO_DATA)
         throw new MyX("No rows in result set", __FILE__, __LINE__);

      bool[] rv;
      rv.length = _nop;
      for (int i = 0; i < _nop; i++)
      {
         MYSQL_BIND* bs = &_obsa[i];
         rv[i] = !bs.is_null_value;
         if (bs.extension !is null)
         {
            BindExt* bx = cast(BindExt*) bs.extension;
            (*bx.pa).length = bs.length_value;
         }
      }
      // In case there were more rows -
      mysql_stmt_reset(_stmt);
      return rv;
   }

   /**
    * Execute a stored function, with any required input variables, and store the return value into a D variable.
    *
    * For this method, no query string is to be provided. The required one is of the form "select foo(?, ? ...)".
    * The method generates it and the appropriate bindings - in, and out. Chunked transfers are not supported
    * in either direction. If you need them, create the parameters separately, then use execPreparedResult()
    * to get a one-row, one-column result set.
    *
    * If it is not possible to convert the column value to the type of target, then execFunction will throw.
    * If the result is NULL, that is indicated by a false return value, and target is unchanged.
    *
    * In the interest of performance, this method assumes that the user has the required information about
    * the number and types of IN parameters and the type of the output variable. In the same interest, if the
    * method is called repeatedly for the same stored function, prepare() is omitted after the first call.
    *
    * Params:
    *    T = The type of the variable to receive the return result.
    *    U = type tuple of args
    *    name = The name of the stored function.
    *    target = the D variable to receive the stored function return result.
    *    args = The list of D variables to act as IN arguments to the stored function.
    *
    * Returns: True if the result was a non-null value.
    */
   bool execFunction(T, U...)(string name, ref T target, U args)
   {
      bool repeatCall = (name == _prevFunc);
      if (_prepared && !repeatCall)
         throw new MyX("You must not prepare a statement before calling execFunction", __FILE__, __LINE__);
      if (!repeatCall)
      {
         _sql = "select " ~ name ~ "(";
         bool comma = false;
         foreach (arg; args)
         {
            if (comma)
               _sql ~= ",?";
            else
            {
               _sql ~= "?";
               comma = true;
            }
         }
         _sql ~= ")";
         prepare();
         _prevFunc = name;
      }
      _nip = 0;
      setInBindings(args);
      if (_inChunked)
         throw new MyX("An input parameter was chunked, but execFunction does not support chunked in parameters.",
                                 __FILE__, __LINE__);
      _nop = 0;
      createParam(target, ParamOut);
      if (_nip)
         bindParams();
      if (mysql_stmt_execute(_stmt))
         throw new MyX(_con.handle, __FILE__, __LINE__);

      bindResults();
      int fr = mysql_stmt_fetch(_stmt);
      if (fr == 1)
         throw new MyX(to!string(mysql_stmt_error(_stmt)), __FILE__, __LINE__);
      if (fr == MYSQL_NO_DATA)
         throw new MyX("No rows in result set", __FILE__, __LINE__);

      MYSQL_BIND* bs = &_obsa[0];
      bool rv = !bs.is_null_value;
      if (bs.extension !is null)
      {
         BindExt* bx = cast(BindExt*) bs.extension;
         (*bx.pa).length = bs.length_value;
      }
      return rv;
   }

   /**
    * Execute a stored procedure, with any required input variables.
    *
    * For this method, no query string is to be provided. The required one is of the form "call proc(?, ? ...)".
    * The method generates it and the appropriate in bindings. Chunked transfers are not supported.
    * If you need them, create the parameters separately, then use execPrepared() or execPreparedResult().
    *
    * In the interest of performance, this method assumes that the user has the required information about
    * the number and types of IN parameters. In the same interest, if the method is called repeatedly for the
    * same stored function, prepare() and other redundant operations are omitted after the first call.
    *
    * OUT parameters are not currently supported. It should generally be possible with MySQL to present
    * them as a result set.
    *
    * Params:
    *    T = The type of the variable to receive the return result.
    *    U = type tuple of args
    *    name = The name of the stored function.
    *    target = the D variable to receive the stored function return result.
    *    args = The list of D variables to act as IN arguments to the stored function.
    *
    */
   void execProcedure(T...)(string name, ref T args)
   {
      bool repeatCall = (name == _prevFunc);
      if (_prepared && !repeatCall)
         throw new MyX("You must not prepare a statement before calling execFunction", __FILE__, __LINE__);
      if (!repeatCall)
      {
         _sql = "call " ~ name ~ "(";
         bool comma = false;
         foreach (arg; args)
         {
            if (comma)
               _sql ~= ",?";
            else
            {
               _sql ~= "?";
               comma = true;
            }
         }
         _sql ~= ")";
         prepare();
         _prevFunc = name;
      }
      _nip = 0;
      setInBindings(args);
      if (_inChunked)
         throw new MyX("An input parameter was chunked, but execFunction does not support chunked in parameters.",
                                 __FILE__, __LINE__);
      if (_nip)
         bindParams();
      if (mysql_stmt_execute(_stmt))
         throw new MyX(_con.handle, __FILE__, __LINE__);
   }

}

unittest
{
   immutable string constr = "host=localhost;user=user;pwd=password;db=mysqld";
   Connection con = new Connection(constr);
   con.reportTruncation(true);

   string escaped = Command.escapeString(con, `O'Rourke has the "biggest one" you've ever seen - \/2 that is`);
   assert(escaped == `O\'Rourke has the \"biggest one\" you\'ve ever seen - \\/2 that is`);


   // These will be used to test a chunked input parameter
   InChunkDelegate sourceFrom(byte[] a)
   {
       uint sent = 0;
       uint pos;
       bool done = false;

       void[] foo(ref uint u)
       {
          pos = sent;
          if (sent+u <= a.length)
          {
             sent += u;
             return a[pos..pos+u];
          }
          else
          {
             u = a.length-sent;
             sent = a.length;
             return a[pos..pos+u];
          }
       }

       return &foo;
   }

   InChunkDelegate generateCrap(int howmuch)
   {
      int limit = howmuch;
      int blocksSent;
      ubyte[] crap;
      crap.length = 65535;
      for (int i = 0; i < 65535; i++)
         crap[i] = cast(ubyte) i%256;

      void[] foo(ref uint u)
      {
         if (blocksSent < limit)
         {
            u = 65535;
            blocksSent++;
            return crap;
         }
         else
         {
            u = 1;
            return crap[0..1];
         }
      }

      return &foo;
   }


// Some variables to match the test table
   int fc;
   bool blv;
   byte bv;
   ubyte ubv;
   short ss;
   ushort us;
   int n, nv;
   uint ui;
   long lv;
   ulong ulv;
   char[] csv;
   char[] vcs;
   byte[] ba;
   MYSQL_DATE d;
   MYSQL_TIMEDIFF t;
   MYSQL_DATETIME dt;
   float fv;
   double dv;

   // Clean up aftr any previous run
   Command clean = Command(con, "delete from basetest");
   ulong ra;
   clean.execSQL(ra);

   // Create a test row
   Command c1 = Command(con);
   c1.sql = "insert into basetest values(" ~
"1, -128, 255, -32768, 65535, 42, 4294967295, -9223372036854775808, 18446744073709551615, 'ABC', " ~
"'The quick brown fox', 0x000102030405060708090a0b0c0d0e0f, '2007-01-01', " ~
"'12:12:12', '2007-01-01 12:12:12', 1.234567890987654, 22.4, NULL)";
   c1.execSQL(ra);
   assert(ra == 1);

   int nrows;
   auto dbc = Command(constr, "select COUNT(intcol) from basetest");
   dbc.execTuple(nrows);
   assert(nrows == 1);

   // Test an insert statement with parameters
   c1.sql = "insert into basetest (bytecol, intcol, stringcol, datecol) values(?, ?, ?, ?)";
   bv = 127;
   c1.createParam(bv);
   n = 1066;
   c1.createParam(n);
   vcs = cast(char[]) "Whatever";
   c1.createParam(vcs);
   d = MYSQL_DATE(1968, 12, 25);
   c1.createParam(d);
   c1.execPrepared(ra);
   c1.reset();
   assert(ra == 1);

   // Test an update statement with parameters representing the new values and the condition variable
   // parameters defined as a bunch with setInBindings()
   c1.sql = "update basetest set bytecol=?, doublecol=? where intcol=?";
   bv = 17;
   dv = 3.333;
   n = 1066;
   c1.setInBindings(bv, dv, n);
   c1.execPrepared(ra);

   // Test execTuple() and verify the prior update
   c1.sql = "select bytecol, doublecol from basetest where intcol=?";
   c1.createParam(n);
   c1.execTuple(bv, dv);
   assert(bv == 17);
   assert(to!string(dv) == "3.333");

   // Check execTuple() with a group of the types
   c1.sql = "select bytecol, ubytecol, shortcol, ushortcol, uintcol, longcol, ulongcol, charscol, stringcol from basetest where intcol=42";
   c1.execTuple(bv, ubv, ss, us, ui, lv, ulv, csv, vcs);
   assert(bv == -128);
   assert(ubv == 255);
   assert(ss == short.min);
   assert(us == ushort.max);
   assert(lv == long.min);
   assert(ulv == ulong.max);
   assert(csv.idup == "ABC");
   assert(vcs.idup == "The quick brown fox");

   // Test the remainer of the types using in parameters for the condition variables
   c1.sql = "select bytescol, datecol, timecol, dtcol, doublecol, floatcol, nullcol from basetest where intcol=? and bytecol=?";
   n = 42;
   c1.createParam(n);
   c1.createParam(bv);
   bool[] brv = c1.execTuple(ba, d, t, dt, dv, fv, nv);
   assert(ba == [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]);
   assert(d.year == 2007 && d.month == 1 && d.day == 1);
   assert(t.hour == 12 && t.minute == 12 && t.second == 12);
   assert(dt.year == 2007 && dt.month == 1 && dt.day == 1 && dt.hour == 12 && dt.minute == 12 && dt.second == 12);
   assert(to!string(dv) == "1.23457");
   assert(to!string(fv) == "22.4");
   assert(brv == [true, true, true, true, true, true, false]);

   // Test a row insert with a chunked IN parameter using a delegate
   byte[] src;
   src.length = 50;
   for (int i = 0; i < 50; i++) src[i] = cast(byte) (i+41);

   c1.sql = "insert into basetest (intcol, bytescol) values(?, ?)";
   n = 77;
   c1.createParam(n);
   InChunkDelegate icd = sourceFrom(src);
   ba.length = 7;
   c1.createParam(ba, ParamIn, 9, 0, icd);
   int params = c1.prepare();
   assert(params == 2);
   c1.execPrepared(ra);
   assert(ra == 1);
   assert(c1._disposition == NON_QUERY && c1._fields == 0);

   c1.sql = "select bytescol from basetest where intcol=77";
   c1.execTuple(ba);
   assert(ba == src);

   // Similar but with default chunking, let execPrepared do the prepare()
   c1.sql = "insert into basetest (intcol, bytescol) values(?, ?)";
   n = 77;
   c1.createParam(n);
   c1.createParam(src, ParamIn, 9);
   c1.execPrepared(ra);
   assert(ra == 1);
   assert(c1._disposition == NON_QUERY && c1._fields == 0);

   c1.sql = "select bytescol from basetest where intcol=77";
   c1.execTuple(ba);
   assert(ba == src);

   // Test error handling when no parameters set up for prepared query
   try
   {
      c1.sql = "update basetest set intcol=24 where bytecol=?";
      params = c1.prepare();
      assert(params == 1);
      c1.execPrepared(ra);
   }
   catch (MyX x)
   {
      string xs = x.toString();
      int pos = std.string.indexOf(xs, "The SQL supplied for the command has placeholders");
      assert(pos > 0);
   }

   c1.sql = "delete from basetest";
   c1.execSQL(ra);

   // Test insertion of multiple rows with update of bound variables
   c1.sql = "insert into basetest (intcol, stringcol) values(?, ?)";
   vcs = cast(char[]) "0";
   n = 0;
   c1.setInBindings(n, vcs);
   for (int i = 0; i < 5; i++)
   {
      c1.execPrepared(ra);
      n++;
      vcs ~= '1';
      c1.updateIP(n);
      c1.updateIP(vcs);
   }
   for (int i = 0; i < 5; i++)
   {
      c1.execPrepared(ra);
      n++;
      vcs ~= '1';
      c1.updateInBindings(n, vcs);
   }

   // We're a bit limited here until we have ResultSet, but
   // execTuple() will do the job after a fashion
   c1.sql = "select stringcol from basetest where intcol=?";
   char[] tmp = ['0'];
   for (int i = 0; i < 10; i++)
   {
      c1.createParam(i);
      c1.execTuple(vcs);
      c1.reset();                // otherwise we'll get a complaint about the statement being prepared
      assert(tmp == vcs);
      tmp ~= '1';
   }

   // Test binding of a struct
   clean.execSQL(ra);
   struct Triplet
   {
      int n;
      string s;
      MYSQL_TIMEDIFF t;
   }
   Triplet three = Triplet( 999, "Whatever", MYSQL_TIMEDIFF(0,0,0,12,12,12));
   c1.sql = "insert into basetest (intcol, stringcol, timecol) values(?, ?, ?)";
   c1.bindInStruct(three);
   c1.execPrepared(ra);
   c1.sql = "select intcol, stringcol, timecol from basetest limit 1";
   three.n = 0;
   three.t = MYSQL_TIMEDIFF.init;
   c1.execTuple(three.n, vcs, three.t);
   assert(three.n == 999 && cast(string) vcs == "Whatever" && three.t.hour == 12 && three.t.minute == 12 && three.t.second == 12);

   // While we're at it, test asking execTuple to put output in a string
   c1.reset();
   try { c1.execTuple(three.n, three.s, three.t); }
   catch (MyX x)
   {
      string xs = x.toString();
      assert(std.string.indexOf(xs, "Target is immutable") > 0);
   }

   // Test binding of a Variant[]
   MyVariant[] va;
   va.length = 3;
   va[0] = 999;
   va[1] = "Whatever";
   va[2] = MYSQL_TIMEDIFF(0,0,0,12,12,12);
   clean.execSQL(ra);
   c1.sql = "insert into basetest (intcol, stringcol, timecol) values(?, ?, ?)";
   c1.bindInArray(va);
   c1.execPrepared(ra);
   c1.sql = "select intcol, stringcol, timecol from basetest limit 1";
   three.n = 0;
   three.t = MYSQL_TIMEDIFF.init;
   c1.execTuple(three.n, vcs, three.t);
   assert(three.n == 999 && cast(string) vcs == "Whatever" && three.t.hour == 12 && three.t.minute == 12 && three.t.second == 12);

   // Test chunked insertion with a delegate into a reasonably large blob
   c1.sql = "delete from tblob";
   c1.execSQL(ra);

   c1.sql = "insert into tblob values(42, ?)";
   ubyte[] dummy;
   icd = generateCrap(50);
   c1.createParam(dummy, ParamIn, 65535, 0, icd);
   c1.prepare();
   c1.execPrepared(ra);

   c1.sql = "select LENGTH(lob) from tblob limit 1";
   c1.execTuple(n);
   assert(n == 65535*50+1);
   // This result to be preserved in tblob for the ResultSet tests

   // Test execFunction()
   string g = "Gorgeous";
   char[] reply;
   c1.reset();
   bool nonNull = c1.execFunction("hello", reply, g);
   assert(nonNull && cast(string) reply == "Hello Gorgeous!");
   g = "Hotlips";
   nonNull = c1.execFunction("hello", reply, g);
   assert(nonNull && cast(string) reply == "Hello Hotlips!");

   // Test execProcedure()
   g = "inserted string 1";
   int m = 2001;
   c1.reset();
   c1.execProcedure("insert2", m, g);

   c1.sql = "select stringcol from basetest where intcol=?";
   c1.createParam(m);
   c1.execTuple(vcs);
   assert(cast(string) vcs == g);
}

   /**
    * A utility class to provide information about the columns of a result set.
    *
    * This provides facilities required by ResultSet and ResultSequence, and a number of methods for relating
    * structs and Variant arrays to columns.
    */
class FieldInfo
{
private:
   MYSQL_FIELD* _pfa;
   uint _fc;
   bool _indexed;
   string[] _colNames;
   uint[string] _fi;
   void* _lastAssoc;
   string[] _sFieldNames;
   string[] _sTypeNames;

   this(MYSQL_FIELD* pfa, uint fc)
   {
      _pfa = pfa;
      _fc = fc;
      _indexed = false;
   }

   enum_field_types type(uint index) { return _pfa[index].type; }
   bool unsigned(uint index)  { return ((_pfa[index].flags & UNSIGNED_FLAG) != 0); }
   uint createLength(uint index)  { return _pfa[index].length; }

   bool checkType(T)(enum_field_types ft)
   {
      static if (is(T == bool))
      {
         return (ft == enum_field_types.MYSQL_TYPE_BIT);
      }
      else static if (is(T == char))
      {
         return (ft == enum_field_types.MYSQL_TYPE_STRING);
      }
      else static if (is(T : ulong))
      {
         switch (T.sizeof)
         {
            case byte.sizeof:
                return (ft == enum_field_types.MYSQL_TYPE_TINY);
            case short.sizeof:
                return (ft == enum_field_types.MYSQL_TYPE_SHORT);
            case int.sizeof:
                return (ft == enum_field_types.MYSQL_TYPE_LONG);
            case long.sizeof:
                return (ft == enum_field_types.MYSQL_TYPE_LONGLONG);
            default:
                return false;
         }
      }
      else static if (is(T == string))
      {
         switch (ft)
         {
            case enum_field_types.MYSQL_TYPE_VARCHAR:
            case enum_field_types.MYSQL_TYPE_VAR_STRING:
            case enum_field_types.MYSQL_TYPE_STRING:
               return true;
            default:
               return false;
         }
      }
      else static if (is(T : ubyte[]))
      {
         switch (ft)
         {
            case enum_field_types.MYSQL_TYPE_VAR_STRING:
            case enum_field_types.MYSQL_TYPE_TINY_BLOB:
            case enum_field_types.MYSQL_TYPE_MEDIUM_BLOB:
            case enum_field_types.MYSQL_TYPE_LONG_BLOB:
            case enum_field_types.MYSQL_TYPE_BLOB:
               return true;
            default:
               return false;
         }
      }
      else static if (is(T : double))
      {
         if (is(T == double))
            return (ft == enum_field_types.MYSQL_TYPE_DOUBLE);
         else
            return (ft == enum_field_types.MYSQL_TYPE_FLOAT);
      }
      else static if (is(T == MYSQL_TIME))
      {
         switch (ft)
         {
            case enum_field_types.MYSQL_TYPE_TIME:
            case enum_field_types.MYSQL_TYPE_DATE:
            case enum_field_types.MYSQL_TYPE_DATETIME:
            case enum_field_types.MYSQL_TYPE_TIMESTAMP:
               return true;
            default:
               return false;
         }
      }
      return false;
   }

   static string[] structFieldNames(S)(S si) if (is(S == struct))
   {
      string s = si.tupleof.stringof[6..$-1];
      string[] parts = split(s, ",");
      string[] names;
      names.length = parts.length;
      foreach(int i, string p; parts)
      {
         string[] pair = split(p, ".");
         names[i] = pair[1];
      }
      return names;
   }

   static string[] structTypeNames(S)(S si) if (is(S == struct))
   {
      string s = typeof(si.tupleof).stringof[1..$-1];
      string[] types = split(s, ", ");
      return types;
   }

   static string dType(enum_field_types colType, uint flags)
   {
      bool unsigned = (flags & UNSIGNED_FLAG) != 0;
      bool isEnum = (flags & ENUM_FLAG) != 0;
      if (isEnum) return "string[]";
      switch (colType)
      {
         case enum_field_types.MYSQL_TYPE_BIT:
            return "bool";
         case enum_field_types.MYSQL_TYPE_DECIMAL:
         case enum_field_types.MYSQL_TYPE_NEWDECIMAL:
            return "char[]";
         case enum_field_types.MYSQL_TYPE_TINY:
            return unsigned? "ubyte": "byte";
			case enum_field_types.MYSQL_TYPE_SHORT:
            return unsigned? "ushort": "short";
			case enum_field_types.MYSQL_TYPE_LONG:
			case enum_field_types.MYSQL_TYPE_INT24:
            return unsigned? "uint": "int";
         case enum_field_types.MYSQL_TYPE_LONGLONG:
            return unsigned? "ulong": "long";
			case enum_field_types.MYSQL_TYPE_FLOAT:
            return "float";
			case enum_field_types.MYSQL_TYPE_DOUBLE:
			   return "double";
			case enum_field_types.MYSQL_TYPE_NULL:
			   return "null";
         case enum_field_types.MYSQL_TYPE_TIMESTAMP:
			case enum_field_types.MYSQL_TYPE_DATE:
			case enum_field_types.MYSQL_TYPE_TIME:
			case enum_field_types.MYSQL_TYPE_DATETIME:
			//case enum_field_types.MYSQL_TYPE_YEAR:
			//case enum_field_types.MYSQL_TYPE_NEWDATE:
			   return "MYSQL_TIME";
			case enum_field_types.MYSQL_TYPE_VARCHAR:
			case enum_field_types.MYSQL_TYPE_VAR_STRING:
			case enum_field_types.MYSQL_TYPE_STRING:
			   return "char[]";
			case enum_field_types.MYSQL_TYPE_TINY_BLOB:
			case enum_field_types.MYSQL_TYPE_MEDIUM_BLOB:
			case enum_field_types.MYSQL_TYPE_LONG_BLOB:
			case enum_field_types.MYSQL_TYPE_BLOB:
			   return "ubyte[]";
			case enum_field_types.MYSQL_TYPE_ENUM:
			case enum_field_types.MYSQL_TYPE_SET:
			   return "char[]";
			case enum_field_types.MYSQL_TYPE_GEOMETRY:
			default:
			   return "";
      }
   }

   static bool isCompatible(string specific, string candidate)
   {
      if (specific == candidate)
         return true;
      switch (specific)
      {
         case "byte":
            return (candidate == "short" || candidate == "int" || candidate == "long");
         case "ubyte":
            return (candidate == "ushort" || candidate == "uint" || candidate == "ulong");
         case "short":
            return (candidate == "int" || candidate == "long");
         case "ushort":
            return (candidate == "uint" || candidate == "ulong");
         case "int":
            return (candidate == "ulong");
         case "uint":
            return (candidate == "ulong");
         case "MYSQL_TIME":
            return (candidate == "MYSQL_DATE" || candidate == "MYSQL_DATETIME" ||
                        candidate == "MYSQL_TIMEDIFF" || candidate == "MYSQL_TIMESTAMP");
         default:
            return false;
      }
   }

public:

   /**
    * Create an index so you can refer to result set columns by name.
    *
    * This will slow things down, so access to column values by name is optional. Use an integer index to access
    * row data if you want the best performance.
    */
   void indexFields()
   {
      if (_indexed)
         return;
      _colNames.length = _fc;
      for (uint i = 0; i < _fc; i++)
      {
         string s = _pfa[i].name[0..strlen(_pfa[i].name)].idup;
         _colNames[i] = s;
         _fi[s] = i;
      }
      _indexed = true;
   }

   /**
    * Check a struct to see if it is compatible with a set of column metadata.
    *
    * The struct must have field names corresponding one to one - order and name - with the
    * column names and types in the result set. The only wiggle room is that integer types in
    * the struct can be bigger than necessary - e.g. long for a column that is byte. However,
    * signed/unsigned mismatches are not tolerated. If the same struct was used for the previous row
    * the name and type checking is skipped.
    *
    * Parameters:
    *    s - a struct instance of some hopefully suitable type
    */
    void checkStruct(S)(ref S s) if (is(S == struct))
    {
       if (_lastAssoc == cast(void*) &s)
          return;
      if (!_indexed)
         indexFields();
      _sFieldNames = structFieldNames(s);
      _sTypeNames = structTypeNames(s);

      // Check that the row is a match for the struct
      foreach(int i, string name; _colNames)
      {
         if (_sFieldNames[i] != name)
            throw new MyX("Field names of row don't match struct at column \""~name~"\".", __FILE__, __LINE__);
         string rowType = dType(_pfa[i].type, _pfa[i].flags);
         if (!isCompatible(rowType, _sTypeNames[i]))
            throw new MyX("Field \""~name~"\" is not compatible with the corresponding struct field.", __FILE__, __LINE__);
      }
    }

   /**
    * Get a column index from a column name
    *
    * Indexing the column names will slow things down narinally, so access to column values by name is
    * optional. Use an integer index to access row data if you want the best performance.
    *
    * Params:
    *    colName = string.
    * Returns:
    *    uint inex of column
    */
   uint index(string colName)
   {
      if (!_indexed)
         indexFields();
      uint* p = (colName in _fi);
      if (p is null)
         throw new MyX("Name supplied to index - \""~colName~"\" is not a field name.", __FILE__, __LINE__);
      return *p;
   }
}


/**
 * For result sets that are expected to contain columns with long data, it may be required
 * to specify that the column result is fetched in chunks.
 *
 * If only a chunk size is specified, the fetching will be chunked at that size, with the array
 * length of the target increased incrementally as required. If a delegate is specified, then chunks of
 * the specified size will be fed to that.
 *
 */
 struct ChunkingSpec
 {
    uint colIndex;
    uint chunkSize;
    OutChunkDelegate ocd;
 }

/**
 * In all flavors of a result set, a row is an array of variants - well, actually MyVariants.
 *
 */
 alias MyVariant[] Row;

/**
 * There is a good deal of common code required for result sets and result sequences, so it lives
 * here in a base class.
 *
 */
class ResultBase
{
private:
   //MYSQL* _handle;
   MYSQL_BIND[] _obsa;
   MYSQL_RES* _pres;
   MYSQL_STMT* _stmt;
   MyVariant[] _va, _uva;  // One for the bind buffers, one sacrificial for the user.
   uint[] _cca;              // column characteristics
   ChunkingSpec[] _csa;    // columns to be chunked
   bool _chunked, _isPrepared, _released;
   uint _fc;
   uint* _lengths;
   FieldInfo _fi;
   ubyte[] _gp;
   ubyte _gash;

   this(bool isPrepared, MYSQL_RES* pres, MYSQL_STMT* stmt, ChunkingSpec[] csa)
   {
      _gp.length=8;
      _isPrepared = isPrepared;
      _pres = pres;
      _stmt = stmt;
      _csa = csa;
      if (!pres)           // dummy default ctor for range
         return;
      _fc = pres.field_count;
      _lengths = pres.lengths;
      _fi = new FieldInfo(pres.fields, _fc);
      _obsa.length = _fc;
      _va.length = _fc;
      _cca.length = _fc;
      for (uint i = 0; i < _fc; i++)
         createParam(i);
   }

   bool colIsChunked(uint colIndex, out uint chunkSize, out OutChunkDelegate ocd)
   {
      if (_csa is null)
         return false;
      foreach( ChunkingSpec cs; _csa)
      {
         if (cs.colIndex == colIndex)
         {
            chunkSize = cs.chunkSize;
            ocd = cs.ocd;
            return true;
         }
      }
      return false;
   }

   void createParam(uint i)
   {
      uint chunkSize;
      OutChunkDelegate outCD;
      if (colIsChunked(i, chunkSize, outCD))
         _chunked = true;        // row must be fetched column wise
      void* pa;
      void* pb;
      enum_field_types ft = _fi.type(i);
      bool uns = _fi.unsigned(i);
      bool at;       // is the column a byte array
      switch (ft)
      {
         case enum_field_types.MYSQL_TYPE_BIT:
            bool b;
            _va[i] = b;
            pb = _va[i].peek!(bool);
            break;
         case enum_field_types.MYSQL_TYPE_TINY:
            if (uns)
            {
               ubyte ub;
               _va[i] = ub;
               pb = _va[i].peek!(ubyte);
            }
            else
            {
               byte sb;
               _va[i] = sb;
               pb = _va[i].peek!(byte);
            }
            break;
         case enum_field_types.MYSQL_TYPE_SHORT:
            if (uns)
            {
               ushort us;
               _va[i] = us;
               pb = _va[i].peek!(ushort);
            }
            else
            {
               short ss;
               _va[i] = ss;
               pb = _va[i].peek!(short);
            }
            break;
         case enum_field_types.MYSQL_TYPE_LONG:
         case enum_field_types.MYSQL_TYPE_INT24:
            if (uns)
            {
               uint ui;
               _va[i] = ui;
               pb = _va[i].peek!(uint);
            }
            else
            {
               int si;
               _va[i] = si;
               pb = _va[i].peek!(int);
            }
            break;
         case enum_field_types.MYSQL_TYPE_LONGLONG:
            if (uns)
            {
               ulong ul;
               _va[i] = ul;
               pb = _va[i].peek!(ulong);
            }
            else
            {
               long sl;
               _va[i] = sl;
               pb = _va[i].peek!(long);
            }
            break;
         case enum_field_types.MYSQL_TYPE_FLOAT:
            float f;
            _va[i] = f;
            pb = _va[i].peek!(float);
            break;
         case enum_field_types.MYSQL_TYPE_DOUBLE:
            double d;
            _va[i] = d;
            pb = _va[i].peek!(double);
            break;
         case enum_field_types.MYSQL_TYPE_VAR_STRING:
         case enum_field_types.MYSQL_TYPE_STRING:
         //case enum_field_types.MYSQL_TYPE_DECIMAL:
         //case enum_field_types.MYSQL_TYPE_NEWDECIMAL:
         case enum_field_types.MYSQL_TYPE_YEAR:
            at = true;
            char[] ca = [ 'x' ];
            _va[i] = ca;
            pa = _va[i].peek!(char[]);
            break;
         case enum_field_types.MYSQL_TYPE_TINY_BLOB:
         case enum_field_types.MYSQL_TYPE_MEDIUM_BLOB:
         case enum_field_types.MYSQL_TYPE_LONG_BLOB:
         case enum_field_types.MYSQL_TYPE_BLOB:
            at = true;
            ubyte[] uba = [ 0 ];
            _va[i] = uba;
            pa = _va[i].peek!(ubyte[]);
            break;
         case enum_field_types.MYSQL_TYPE_DATE:
            MYSQL_DATE date;
            _va[i] = date;
            pb = _va[i].peek!(MYSQL_DATE);
            break;
         case enum_field_types.MYSQL_TYPE_DATETIME:
            MYSQL_DATETIME datetime;
            _va[i] = datetime;
            pb = _va[i].peek!(MYSQL_DATETIME);
            break;
         case enum_field_types.MYSQL_TYPE_TIMESTAMP:
            MYSQL_TIMESTAMP ts;
            _va[i] = ts;
            pb = _va[i].peek!(MYSQL_TIMESTAMP);
            break;
         case enum_field_types.MYSQL_TYPE_TIME:
            MYSQL_TIMEDIFF time;
            _va[i] = time;
            pb = _va[i].peek!(MYSQL_TIMEDIFF);
            break;
         default:
            throw new MyX("Unsupported type passed to PreparedRow:createVariantParam() - " ~ to!string(ft), __FILE__, __LINE__);
            break;
      }
      MYSQL_BIND* bsout = &_obsa[i];
      uint length = _fi.createLength(i);
      if (at)
      {
         _cca[i] = 1;
         BindExt* bx = new BindExt();
         bsout.extension = bx;
         bx.pa = cast(ubyte[]*) pa;
         bx.chunkSize = chunkSize;
         bx.outCD = outCD;
         if (bx.chunkSize)
         {
            _cca[i] = 2;
            bx.chunkBuffer.length = chunkSize;
            bsout.buffer = bx.chunkBuffer.ptr;
         }
         else
            bsout.buffer = (*bx.pa).ptr;
         bsout.buffer_length = length;
         bsout.length = &bsout.length_value;
         bsout.is_null = &bsout.is_null_value;
      }
      else
      {
         bsout.buffer = pb;
         bsout.buffer_length = _va[i].type.tsize;
         bsout.is_null = &bsout.is_null_value;
      }
      bsout.buffer_type = ft;
      bsout.is_unsigned = uns? 1: 0;
   }

   void nativeRowToVariants(MYSQL_ROW nr)
   {
      foreach (int i, MyVariant v; _uva)
      {
         enum_field_types ft = _fi.type(i);
         if (nr[i] is null)
         {
            continue;      // _uva[i] will have un-initialized value, testable with .hasValue()
         }
         string val = cast(string) nr[i][0.._lengths[i]];
         bool uns = _fi.unsigned(i);
         bool at;       // is the column a byte array
         switch (ft)
         {
            case enum_field_types.MYSQL_TYPE_BIT:
               val = val[0]? "true": "false";
               _uva[i] = to!bool(val);
               break;
            case enum_field_types.MYSQL_TYPE_TINY:
               if (uns)
                  _uva[i] = to!ubyte(val);
               else
                  _uva[i] = to!byte(val);
               break;
            case enum_field_types.MYSQL_TYPE_SHORT:
               if (uns)
                  _uva[i] = to!ushort(val);
               else
                  _uva[i] = to!short(val);
               break;
            case enum_field_types.MYSQL_TYPE_LONG:
            case enum_field_types.MYSQL_TYPE_INT24:
               if (uns)
                  _uva[i] = to!uint(val);
               else
                  _uva[i] = to!int(val);
               break;
            case enum_field_types.MYSQL_TYPE_LONGLONG:
               if (uns)
                  _uva[i] = to!ulong(val);
               else
                  _uva[i] = to!long(val);
               break;
            case enum_field_types.MYSQL_TYPE_FLOAT:
               _uva[i] = to!float(val);
               break;
            case enum_field_types.MYSQL_TYPE_DOUBLE:
               _uva[i] = to!double(val);
               break;
            case enum_field_types.MYSQL_TYPE_VAR_STRING:
            case enum_field_types.MYSQL_TYPE_STRING:
            //case enum_field_types.MYSQL_TYPE_DECIMAL:
            //case enum_field_types.MYSQL_TYPE_NEWDECIMAL:
            case enum_field_types.MYSQL_TYPE_YEAR:
               _uva[i] = to!(char[])(val);
               break;
            case enum_field_types.MYSQL_TYPE_TINY_BLOB:
            case enum_field_types.MYSQL_TYPE_MEDIUM_BLOB:
            case enum_field_types.MYSQL_TYPE_LONG_BLOB:
            case enum_field_types.MYSQL_TYPE_BLOB:
               ubyte[] t = cast(ubyte[]) nr[i][0.._lengths[i]];
               _uva[i] = t;
               break;
            case enum_field_types.MYSQL_TYPE_DATE:
               _uva[i] = cast(MYSQL_DATE) toMyTime(val, ft);
               break;
            case enum_field_types.MYSQL_TYPE_DATETIME:
               _uva[i] = cast(MYSQL_DATETIME) toMyTime(val, ft);
               break;
            case enum_field_types.MYSQL_TYPE_TIMESTAMP:
               _uva[i] = cast(MYSQL_TIMESTAMP) toMyTime(val, ft);
               break;
            case enum_field_types.MYSQL_TYPE_TIME:
               _uva[i] = cast(MYSQL_TIMEDIFF) toMyTime(val, ft);
               break;
            default:
               throw new MyX("Unsupported type passed to PreparedRow:createVariantParam() - " ~ to!string(ft), __FILE__, __LINE__);
               break;
         }
      }
   }

   void doChunkedOutTransfer(int colIndex)
   {
      MYSQL_BIND* bs = &_obsa[colIndex];
      BindExt* bx = cast(BindExt*) _obsa[colIndex].extension;
      OutChunkDelegate ocd = bx.outCD;

      if (ocd !is null)
      {
         uint offset = 0;
         int fetchResult;
         bs.buffer_length = bx.chunkSize;
         bool finished = false;

         for (;;)
         {
            fetchResult = mysql_stmt_fetch_column(_stmt, bs, colIndex, offset);
            if (fetchResult != 0 && fetchResult != 2051)
               //const char* s = mysql_stmt_error(_stmt);
               throw new MyX(to!string(mysql_stmt_error(_stmt)), __FILE__, __LINE__);
            uint avail = bs.length_value;
            uint tail = bx.chunkSize;
            if (offset+bx.chunkSize >= avail)
            {
               tail = avail-offset;
               finished = true;
            }
            ocd(cast(ubyte*) bs.buffer, tail, avail);
            if (finished)
               break;
            offset += bx.chunkSize;
         }
      }
      else
      {
         uint offset = 0;
         int fetchResult;
         bool finished = false;
         (*bx.pa).length = 0;

         for (bool allocated = false;;)
         {
            fetchResult = mysql_stmt_fetch_column(_stmt, bs, colIndex, offset);
            if (fetchResult != 0 && fetchResult != 2051)
            {
               //const char* s = mysql_stmt_error(_stmt);
               throw new MyX(to!string(mysql_stmt_error(_stmt)), __FILE__, __LINE__);
            }
            uint avail = bs.length_value;

            uint tail = bx.chunkSize;
            if (offset+bx.chunkSize >= avail)
            {
               tail = avail-offset;
               finished = true;
            }
            if (!allocated)
            {
               (*bx.pa).length = avail;
               allocated = true;
            }
            (*bx.pa)[offset..offset+tail] = cast(ubyte[]) bx.chunkBuffer[0..tail];
            if (finished)
               break;
            offset += bx.chunkSize;
         }
      }
   }

   void bindResults()
   {
      for (int i = 0; i < _fc; i++)
      {
         size_t ml = _stmt.fields[i].length;    // table create length
         MYSQL_BIND* bp = &_obsa[i];
         if (!_cca[i])
            continue;
         BindExt* bx = cast(BindExt*) bp.extension;
         //size_t ml = _stmt.fields[i].length;    // table create length
         if (bx.chunkSize)
         {
            bx.chunkBuffer.length = bx.chunkSize;
            bp.buffer = bx.chunkBuffer.ptr;
            bp.buffer_length = bx.chunkSize;
         }
         else
         {
            (*bx.pa).length = ml;
            bp.buffer = (*bx.pa).ptr;
            bp.buffer_length = ml;
         }
      }
      if (mysql_stmt_bind_result(_stmt, _obsa.ptr))
         throw new MyX(to!string(mysql_stmt_error(_stmt)), __FILE__, __LINE__);
   }

   void adjustArrays()        // Also checks for null columns
   {
      for (uint i = 0; i < _fc; i++)
      {
         MYSQL_BIND* bp = &_obsa[i];
         if (bp.is_null_value)
         {
            MyVariant tv;
            _uva[i] = tv;     // swap it for an uninitialized one
            continue;
         }
         if (_cca[i] == 1)    // some kind of array of bytes and not chunked
         {
            // Should modify _cca values to indicate exact type
            if (_uva[i].type == typeid(char[]))
            {
               char[]* cap = _uva[i].peek!(char[]);
               (*cap).length = _obsa[i].length_value;
            }
            else if (_uva[i].type == typeid(byte[]))
            {
               byte[]* bap = _uva[i].peek!(byte[]);
               (*bap).length = _obsa[i].length_value;
            }
            else
            {
               ubyte[]* ubap = _uva[i].peek!(ubyte[]);
               (*ubap).length = _obsa[i].length_value;
            }
         }
      }
   }

public:

   /**
    * Populate a matching struct with the values from the current row.
    *
    * The struct must have field names corresponding one to one - order and name - with the
    * column names and types in the result set. The only wiggle room is that integer types in
    * the struct can be bigger than necessary - e.g. long for a column that is byte. However,
    * signed/unsigned mismatches are not tolerated. If the same struct was used for the previous row
    * the name and type checking is skipped.
    *
    * Parameters:
    *    s - a struct instance of a suitable type
    */
   void rowToStruct(S)(ref S s) if (is(S == struct))
   {
      _fi.checkStruct(s);
      // OK, so everything matches
      foreach (i, dummy; s.tupleof)
      {
         s.tupleof[i] = _uva[i].hasValue()? _uva[i].get!(typeof(s.tupleof[i])): typeof(s.tupleof[i]).init;
      }
   }

   /**
    * Get a column value by index into a D variable from the current row
    *
    * Params:
    *   T = The type of the target variable.
    *   target =  An instance of that type.
    *   index = The column number within the result set starting at zero.
    *   isnull = An out variable that will be set to true if the column was NULL.
    *
    * Returns:
    *   The value populated.
    */
   T getValue(T)(out T target, int index, out bool isnull)
   {
      isnull = !_uva[index].hasValue(Ş);
      if (isnull)
         return target;
      if (_uva[index].type != typeid(T))
            throw new MyX("Type requested in getValue does not match the column type", __FILE__, __LINE__);

      target = _uva[index].get!(T);
      return target;
   }

   /**
    * Get a column value by column name into a D variable from the current row
    *
    * Params:
    *   T = The type of the target variable.
    *   target =  An instance of that type.
    *   name = The column name.
    *   isnull = An out variable that will be set to true if the column was NULL.
    *
    * Returns:
    *   The value populated.
    */
   T getValue(T)(out T target, string name, out bool isnull)
   {
      uint index = _fi.index(name);
      target = getValue(target, index, isnull);
      return target;
   }

   /**
    * Convert the current row into an associative array of MyVariant indexed by column name.
    *
    *
    * Returns:
    *   MyVariant[string] array containing the row data.
    */
   MyVariant[string] rowAsVAA()
   {
      _fi.indexFields();      // NOP if already done
      MyVariant[string] vaa;
      foreach (uint i, MyVariant v; _uva)
         vaa[_fi._colNames[i]] = v;
      return vaa;
   }

   /**
    * Get a column value as a string.
    *
    */
   string asString(uint col) { return _uva[col].toString(); }
}

/**
 * An object to give convenient access to a complete result set.
 *
 * After executing a query that produces a result set, you have two choices as to how to proceed.
 * This facility covers the case when you choose to buffer the entire set of results to the client.
 *
 * The result set in this case becomes a random-access Range of Rows - MyVariant[].
 *
 * The Variant arrays are created lazily, but the result is not cached, so if you visit the rame row
 * more than once there is some overhead in reconstituting the MyVariant[]. User should cache if required.
 */
class ResultSet: ResultBase
{
private:
   size_t[] _rb;
   ulong _cr;
   ulong _rc;
   bool isSave;

private:


   void doColumnWiseFetch()
   {
      int r = mysql_stmt_fetch(_stmt);
      if (r == MYSQL_NO_DATA)
         throw new MyX("Unexpected end of data", __FILE__, __LINE__);
      else if (r == 1)
         throw new MyX(to!string(mysql_stmt_error(_stmt)), __FILE__, __LINE__);
      // If any columns are chunked, we have to fetch the row a column at a time
      for (uint i = 0; i < _fc; i++)
      {
         if (_cca[i] == 2)
            doChunkedOutTransfer(i);
         else
            mysql_stmt_fetch_column(_stmt, &_obsa[i], i, 0);
      }
   }

   void doRegularFetch()
   {
      int r = mysql_stmt_fetch(_stmt);
      if (r == MYSQL_NO_DATA)
         throw new MyX("Unexpected end of data", __FILE__, __LINE__);
      else if (r == MYSQL_DATA_TRUNCATED)
         throw new MyX("Some output data was too long for the supplied variable", __FILE__, __LINE__);
      else if (r == 1)
         throw new MyX(to!string(mysql_stmt_error(_stmt)), __FILE__, __LINE__);
   }

   void fetchPreparedRow(ulong n)
   {
      if (n >= _rc)
            throw new MyX("Attempting to fetch an out of range row.", __FILE__, __LINE__);
      mysql_stmt_data_seek(_stmt, n);
      if (_chunked)
         doColumnWiseFetch();
      else
         doRegularFetch();
      _uva = _va.dup;
      adjustArrays();
   }


   void fetchRawRow(ulong n)
   {
      mysql_data_seek(_pres, n);
      MYSQL_ROW myrow = mysql_fetch_row(_pres);
      _lengths = mysql_fetch_lengths(_pres);
      nativeRowToVariants(myrow);
   }

   this()
   {
      super(false, null, null, null);
      isSave = true;
   }

   /**
    * Constructor to tie the ResultSet to a MYSQL_RES struct - execSQLResult()
    *
    * You shoud not need to use this constructor in your code, as you will be handed a ResultSet
    * by one of the Command methods.
    *
    * Params:
    *   pres = The MYSQL_RES*.
    */

   this(MYSQL_RES* pres)
   {
      super(false, pres, null, null);
      _rc = pres.row_count;
      _uva.length = pres.field_count;
      if (_rc)
         fetchRawRow(0);   // This places into _va
      if (_rc > size_t.max)
         throw new MyX("Result set not representable as a range on this system.", __FILE__, __LINE__);
      _rb.length = cast(uint) _rc;
      for (uint i = 0; i < cast(uint) _rc; i++)
         _rb[i] = i;
   }


   /**
    * Constructor to tie the ResultSet to a MYSQL_STMT and its metadata - execPreparedResult()
    *
    * You should not need to use this constructor in your code, as you will be handed a ResultSet
    * by one of the Command methods.
    *
    * Params:
    *   stmt = The MYSQL_STMT*.
    *   csa = Array of ChinkingSpec.
    */

   this(MYSQL_STMT* stmt, ChunkingSpec[] csa)
   {
      MYSQL_RES* pmetaRes= mysql_stmt_result_metadata(stmt);
      super(true, pmetaRes, stmt, csa);
      bindResults();
      mysql_stmt_store_result(stmt);
      _rc = mysql_stmt_num_rows(stmt);
      if (_rc)
         fetchPreparedRow(0);
      if (_rc > size_t.max)
         throw new MyX("Result set not representable as a range on this system.", __FILE__, __LINE__);
      _rb.length = cast(size_t) _rc;
      for (uint i = 0; i < cast(uint) _rc; i++)
         _rb[i] = i;
   }

public:


   /**
    * Make the ResultSet behave as a random access range - empty
    *
    */
   @property bool empty() { return (_rb.length == 0); }
   /**
    * Make the ResultSet behave as a random access range - save
    *
    * I am currently not clear exactly how this should be done. Maybe Ranges that require save
    * should also require restore? As it is, the ResultSet object returned from save only contains
    * the array of uints that index into the actual result set rows. Maybe I should provide the
    * restore() method?
    */
   @property ResultSet save()
   {
      ResultSet saved = new ResultSet();
      saved._rb = _rb;
      // If you need to restore you'll have to copy _rb back from the saved copy, which is
      // otherwise useless.
      return saved;
   }
   /**
    * Make the ResultSet behave as a random access range - front
    *
    * Gets the first row in whatever remains of the Range.
    */
   @property Row front()
   {
      if (!_rb.length)
         throw new MyX("Attempted 'front' on empty result set.", __FILE__, __LINE__);
      uint i = _rb[0];
      // _cr is the current row in terms of the row set - not the range
      if (i != _cr)
      {
         if (_isPrepared)
            fetchPreparedRow(cast(ulong) i);
         else
            fetchRawRow(cast(ulong) i);
      }
      _cr = i;
       return _uva;
   }
   /**
    * Make the ResultSet behave as a random access range - back
    *
    * Gets the last row in whatever remains of the Range.
    */
   @property Row back()
   {
      if (!_rb.length)
         throw new MyX("Attempted 'back' on empty result set.", __FILE__, __LINE__);
      uint i = _rb[$-1];
      if (i != _cr)
      {
         if (_isPrepared)
            fetchPreparedRow(cast(ulong) i);
         else
            fetchRawRow(cast(ulong) i);
      }
      _cr = i;
      return _uva;
   }
   /**
    * Make the ResultSet behave as a random access range - popFront()
    *
    */
   void popFront()
   {
      if (!_rb.length)
         throw new MyX("Attempted 'popFront' on empty result set.", __FILE__, __LINE__);
      _rb= _rb[1 .. $];
   }
   /**
    * Make the ResultSet behave as a random access range - popBack
    *
    */
   void popBack()
   {
      if (!_rb.length)
         throw new MyX("Attempted 'popBack' on empty result set.", __FILE__, __LINE__);
      // Fetch the required row
      _rb= _rb[0 .. $-1];
   }
   /**
    * Make the ResultSet behave as a random access range - opIndex
    *
    * Gets the i'th row of whatever remains of the range
    */
   Row opIndex(size_t i)
   {
      if (!_rb.length)
         throw new MyX("Attempted to index into an empty result set.", __FILE__, __LINE__);
      if (i >= _rb.length)
         throw new MyX("Requested range index out of range", __FILE__, __LINE__);
      i = _rb[i];
      if (i !=_cr)
      {
         if (_isPrepared)
            fetchPreparedRow(cast(ulong) i);
         else
            fetchRawRow(cast(ulong) i);
      }
      _cr = i;
      return _uva;
   }
   /**
    * Make the ResultSet behave as a random access range - length
    *
    */
   @property size_t length() { return _rb.length; }


   /**
    * Explicitly clean up the MySQL resources and cancel pending results
    *
    */
   void close()
   {
      if (_isPrepared)
      {
         if (!_released)
         {
            mysql_stmt_free_result(_stmt);
            //mysql_stmt_close(_stmt);
            _released = true;
         }
      }
      else
      {
         if (!_released)
         {
            mysql_free_result(_pres);
            _released = true;
         }
      }
   }

   /**
    * Clean up the MySQL resources.
    *
    * This will not happen until the GC collects the ResultSet object, so consider getting it in the
    * first place with:
    *
    * scope ResultSet = execResult();
    *
    * Close checks to see if it has already been called, so close() amd the destructor coexist happily.
    */
   ~this()
   {
      close();
   }
}

unittest
{
   immutable string constr = "host=localhost;user=user;pwd=password;db=mysqld";
   Connection con = new Connection(constr);
   con.reportTruncation(true);

   static assert(isRandomAccessRange!(ResultSet));
   struct TestStruct
   {
      bool boolcol;
      byte bytecol;
      ubyte ubytecol;
      short shortcol;
      ushort ushortcol;
      int intcol;
      uint uintcol;
      long longcol;
      ulong ulongcol;
      char[] charscol;
      char[] stringcol;
      ubyte[] bytescol;
      MYSQL_DATE datecol;
      MYSQL_TIMEDIFF timecol;
      MYSQL_DATETIME dtcol;
      double doublecol;
      float floatcol;
      int nullcol;
   }

   struct X
   {
      int intcol;
      char[] stringcol;
   }

   Command cleanup = Command(con, "delete from basetest");
   ulong ra;
   cleanup.execSQL(ra);

   Command c2 = Command(con, "insert into basetest values(" ~
"1, -128, 255, -32768, 65535, 42, 4294967295, -9223372036854775808, 18446744073709551615, 'ABC', " ~
"'The quick brown fox', 0x000102030405060708090a0b0c0d0e0f, '2007-01-01', " ~
"'12:12:12', '2007-01-01 12:12:12', 1.234567890987654, 22.4, NULL)");
   c2.execSQL(ra);

   c2.sql = "select * from basetest";
   ResultSet rs = c2.execSQLResult();
   Row r = rs.front;
   assert(r.length == 18);
   assert(r[0].type == typeid(bool) && r[0] == true);
   assert(r[1].type == typeid(byte) && r[1] == -128);
   assert(r[2].type == typeid(ubyte) && r[2] == 255);
   assert(r[3].type == typeid(short) && r[3] == short.min);
   assert(r[4].type == typeid(ushort) && r[4] == ushort.max);
   assert(r[5].type == typeid(int) && r[5] == 42);
   assert(r[6].type == typeid(uint) && r[6] == uint.max);
   assert(r[7].type == typeid(long) && r[7] == long.min);
   assert(r[8].type == typeid(ulong) && r[8] == ulong.max);
   assert(r[9].type == typeid(char[]) && r[9] == ['A','B','C']);
   assert(r[10].type == typeid(char[]) && r[10] == cast(char[]) "The quick brown fox");
   assert(r[11].type == typeid(ubyte[]) && r[11] == cast(ubyte[]) [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]);
   MYSQL_DATE d = r[12].get!(MYSQL_DATE);
   assert(d.year == 2007 && d.month == 1 && d.day == 1);
   MYSQL_TIMEDIFF t = r[13].get!(MYSQL_TIMEDIFF);
   assert(t.hour == 12 && t.minute == 12 && t.second == 12);
   MYSQL_DATETIME dt = r[14].get!(MYSQL_DATETIME);
   assert(dt.year == 2007 && dt.month == 1 && dt.day == 1 && dt.hour == 12 && dt.minute == 12 && dt.second == 12);
   assert(r[15].type == typeid(double) && r[15].toString() == to!string(1.234567890987654));
   assert(r[16].type == typeid(float) && r[16].toString() == to!string(22.4f));
   assert(!r[17].hasValue());

   c2.sql = "select * from basetest";
   rs = c2.execPreparedResult();
   r = rs.front;
   assert(r[0].type == typeid(bool) && r[0] == true);
   assert(r[1].type == typeid(byte) && r[1] == -128);
   assert(r[2].type == typeid(ubyte) && r[2] == 255);
   assert(r[3].type == typeid(short) && r[3] == short.min);
   assert(r[4].type == typeid(ushort) && r[4] == ushort.max);
   assert(r[5].type == typeid(int) && r[5] == 42);
   assert(r[6].type == typeid(uint) && r[6] == uint.max);
   assert(r[7].type == typeid(long) && r[7] == long.min);
   assert(r[8].type == typeid(ulong) && r[8] == ulong.max);
   assert(r[9].type == typeid(char[]) && r[9] == ['A','B','C']);
   assert(r[10].type == typeid(char[]) && r[10] == cast(char[]) "The quick brown fox");
   assert(r[11].type == typeid(ubyte[]) && r[11] == cast(ubyte[]) [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]);
   d = r[12].get!(MYSQL_DATE);
   assert(d.year == 2007 && d.month == 1 && d.day == 1);
   t = r[13].get!(MYSQL_TIMEDIFF);
   assert(t.hour == 12 && t.minute == 12 && t.second == 12);
   dt = r[14].get!(MYSQL_DATETIME);
   assert(dt.year == 2007 && dt.month == 1 && dt.day == 1 && dt.hour == 12 && dt.minute == 12 && dt.second == 12);
   assert(r[15].type == typeid(double) && r[15].toString() == to!string(1.234567890987654));
   assert(r[16].type == typeid(float) && r[16].toString() == to!string(22.4f));
   assert(!r[17].hasValue());

   TestStruct teststruct;
   teststruct.nullcol = 999;
   rs.rowToStruct(teststruct);
   assert(teststruct.bytecol == -128 && teststruct.longcol == long.min && teststruct.nullcol == 0);
   rs.close();

   cleanup.execSQL(ra);
   string seq = "0123456789abcdef";

   c2.sql = "insert into basetest (intcol, stringcol) values(?, ?)";
   int m = 0;
   char[] ss;
   c2.setInBindings(m, ss);
   for (; m < 16; m++)
   {
      ss = cast(char[]) seq[0..m+1];
      c2.updateIP(ss);
      c2.execPrepared(ra);
   }
   c2.sql = "select intcol, stringcol from basetest";
   rs = c2.execSQLResult();
   for (int i = 0; i < 16; i++)
   {
      Row tr = rs[i];
      assert(tr[0] == i && cast(string) tr[1].get!(char[]) == seq[0..i+1]);
   }

   while (!rs.empty)
   {
      Row tr = rs.back;
      rs.popBack();
   }
   assert(rs._rb.length == 0);
   rs.close();

   rs = c2.execPreparedResult();
   for (int i = 0; i < 16; i++)
   {
      Row tr = rs[i];
      assert(tr[0] == i && cast(string) tr[1].get!(char[]) == seq[0..i+1]);
   }

   while (!rs.empty)
   {
      Row tr = rs.back;
      rs.popBack();
   }
   assert(rs._rb.length == 0);
   rs.close();

   // Test a result set with a chunked column and a delegate
   OutChunkDelegate trashBin(ref ulong requestedCount, ref ulong actualCount, ref ubyte[] prefix)
   {
      bool reported = false;

      // This will be the delegate. It gets passed a pointer to a buffer that will contain bx.chunkSize
      // bytes until the last chunk, which will be less than that.
      void foo(ubyte* a, uint cs, ulong ts)
      {
         if (!reported)
         {
            ubyte[] uba = cast(ubyte[]) a[0..10];
            prefix = uba[0..10].dup;
            requestedCount = ts;
            reported = true;
         }
         // check the passed buffer
         if (!(cs == 65535 || cs == 1))
            throw new Exception("Expected buffers to be 65535 or 1 length");
         if (cs == 1)
         {
            if (a[0] != 0)
               throw new Exception("Expected buffer of length 1 to contain zero byte");
         }
         else
         {
            for (int i = 0; i < 65535; i++)
            {
               if (a[i] != i%256)
                  throw new Exception("Expected buffer of length 65535 to contain cyclic values i%256");
            }
         }
         actualCount += cs;
      }

      return &foo;
   }

   ulong reported, actual;
   ubyte[] prefix;
   c2.sql = "select * from tblob limit 1";
   ChunkingSpec[] csa;
   csa ~= ChunkingSpec(1, 65535, trashBin(reported, actual, prefix));
   rs = c2.execPreparedResult(csa);
   r = rs.front;
   assert(reported == 65535*50+1 && actual == reported && to!(string)(prefix) == "[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]");

   rs.close();
}

/**
 * An object to give convenient access to a result set one row at a time.
 *
 * After doing a query that produces a result set, you have two choices as to how to proceed.
 * This facility covers the case when you choose to deal with the rows sequentially.
 *
 * The result set in this case becomes an Input Range of Rows - MyVariant[].
 *
 */
class ResultSequence: ResultBase
{
private:
   bool _empty;

private:

   bool doColumnWiseFetch()
   {
      int r = mysql_stmt_fetch(_stmt);
      if (r == MYSQL_NO_DATA)
         return false;
      else if (r == 1)
         throw new MyX(to!string(mysql_stmt_error(_stmt)), __FILE__, __LINE__);
      // If any columns are chunked, we have to fetch the row a column at a time
      for (uint i = 0; i < _fc; i++)
      {
         if (_cca[i] == 2)
            doChunkedOutTransfer(i);
         else
            mysql_stmt_fetch_column(_stmt, &_obsa[i], i, 0);
      }
      return true;
   }

   bool doRegularFetch()
   {
      int r = mysql_stmt_fetch(_stmt);
      if (r == MYSQL_NO_DATA)
         return false;
      else if (r == MYSQL_DATA_TRUNCATED)
         throw new MyX("Some output data was too long for the supplied variable", __FILE__, __LINE__);
      else if (r == 1)
         throw new MyX(to!string(mysql_stmt_error(_stmt)), __FILE__, __LINE__);
      return true;
   }

   bool fetchPreparedRow()
   {
      bool rv;
      if (_chunked)
         rv = doColumnWiseFetch();
      else
         rv = doRegularFetch();
      if (!rv)
         return false;
      _uva = _va.dup;
      adjustArrays();
      return true;
   }


   bool fetchRawRow()
   {
      MYSQL_ROW myrow = mysql_fetch_row(_pres);
      if (myrow is null)
         return false;
      _lengths = mysql_fetch_lengths(_pres);
      nativeRowToVariants(myrow);
      return true;
   }

   // Default consructor for Range
   this()
   {
      super(false, null, null, null);
   }

   /**
    * Constructor to tie the ResultSequence to a MYSQL_RES returned by mysql_store_result().
    *
    * You shoud not need to use this constructor in your code, as you will be handed a ResultSequence
    * by one of the Command methods.
    *
    * Params:
    *   pres = The MYSQL_RES*.
    */

   this(MYSQL_RES* pres)
   {
      super(false, pres, null, null);
      _uva.length = pres.field_count;
      if (!fetchRawRow())
         _empty = true;
   }


   /**
    * Constructor to tie the ResultSequence to a MYSQL_STMT and its metadata.
    *
    * You should not need to use this constructor in your code, as you will be handed a ResultSequence
    * by one of the Command methods.
    *
    * Params:
    *    stmt = The MYSQL_STMT*.
    *    csa = Array of ChunkingSpec
    */

   this(MYSQL_STMT* stmt, ChunkingSpec[] csa)
   {
      MYSQL_RES* pmetaRes= mysql_stmt_result_metadata(stmt);
      super(true, pmetaRes, stmt, csa);
      bindResults();
      if (!fetchPreparedRow())
         _empty = true;
   }

public:


   /**
    * Make the ResultSequence behave as an Input Range - empty
    *
    */
   @property bool empty() { return _empty; }
   /**
    * Make the ResultSequence behave as a random access range - front
    *
    * Gets the current row
    */
   @property Row front()
   {
      if (_empty)
         throw new MyX("Attempted 'front' on empty result set.", __FILE__, __LINE__);
       return _uva;
   }
   /**
    * Make the ResultSequence behave as a random access range - popFront()
    *
    * Progresses to the next row of the result set - that will then be 'front'
    */
   void popFront()
   {
      if (_empty)
         throw new MyX("Attempted 'popFront' when no more rows available", __FILE__, __LINE__);
      if (_isPrepared)
         _empty = !fetchPreparedRow();
      else
         _empty = !fetchRawRow();
   }

   /**
    * Explicitly clean up the MySQL resources and cancel pending results
    *
    */
   void close()
   {
      if (!_released)
      {
         mysql_free_result(_pres);
         _released = true;
      }
   }

   /**
    * Clean up the MySQL resources.
    *
    * This will not happen until the GC collects the ResultSequence object, so consider getting it in the
    * first place with:
    *
    * scope ResultSequence = execResultSequence();
    */
   ~this()
   {
      close();
   }
}

unittest
{
   immutable string constr = "host=localhost;user=user;pwd=password;db=mysqld";
   Connection con = new Connection(constr);
   con.reportTruncation(true);

   static assert(isInputRange!(ResultSequence));
   struct TestStruct
   {
      bool boolcol;
      byte bytecol;
      ubyte ubytecol;
      short shortcol;
      ushort ushortcol;
      int intcol;
      uint uintcol;
      long longcol;
      ulong ulongcol;
      char[] charscol;
      char[] stringcol;
      ubyte[] bytescol;
      MYSQL_DATE datecol;
      MYSQL_TIMEDIFF timecol;
      MYSQL_DATETIME dtcol;
      double doublecol;
      float floatcol;
      int nullcol;
   }

   struct X
   {
      int intcol;
      char[] stringcol;
   }

   Command cleanup = Command(con, "delete from basetest");
   ulong ra;
   cleanup.execSQL(ra);

   Command c3 = Command(con, "insert into basetest values(" ~
"1, -128, 255, -32768, 65535, 42, 4294967295, -9223372036854775808, 18446744073709551615, 'ABC', " ~
"'The quick brown fox', 0x000102030405060708090a0b0c0d0e0f, '2007-01-01', " ~
"'12:12:12', '2007-01-01 12:12:12', 1.234567890987654, 22.4, NULL)");
   c3.execSQL(ra);

   c3.sql = "select * from basetest";
   ResultSequence rs = c3.execSQLSequence();
   Row r = rs.front;
   assert(r.length == 18);
   assert(r[0].type == typeid(bool) && r[0] == true);
   assert(r[1].type == typeid(byte) && r[1] == -128);
   assert(r[2].type == typeid(ubyte) && r[2] == 255);
   assert(r[3].type == typeid(short) && r[3] == short.min);
   assert(r[4].type == typeid(ushort) && r[4] == ushort.max);
   assert(r[5].type == typeid(int) && r[5] == 42);
   assert(r[6].type == typeid(uint) && r[6] == uint.max);
   assert(r[7].type == typeid(long) && r[7] == long.min);
   assert(r[8].type == typeid(ulong) && r[8] == ulong.max);
   assert(r[9].type == typeid(char[]) && r[9] == ['A','B','C']);
   assert(r[10].type == typeid(char[]) && r[10] == cast(char[]) "The quick brown fox");
   assert(r[11].type == typeid(ubyte[]) && r[11] == cast(ubyte[]) [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]);
   MYSQL_DATE d = r[12].get!(MYSQL_DATE);
   assert(d.year == 2007 && d.month == 1 && d.day == 1);
   MYSQL_TIMEDIFF t = r[13].get!(MYSQL_TIMEDIFF);
   assert(t.hour == 12 && t.minute == 12 && t.second == 12);
   MYSQL_DATETIME dt = r[14].get!(MYSQL_DATETIME);
   assert(dt.year == 2007 && dt.month == 1 && dt.day == 1 && dt.hour == 12 && dt.minute == 12 && dt.second == 12);
   assert(r[15].type == typeid(double) && r[15].toString() == to!string(1.234567890987654));
   assert(r[16].type == typeid(float) && r[16].toString() == to!string(22.4f));
   assert(!r[17].hasValue());
   rs.close();

   c3.sql = "select * from basetest";
   rs = c3.execPreparedSequence();
   r = rs.front;
   assert(r[0].type == typeid(bool) && r[0] == true);
   assert(r[1].type == typeid(byte) && r[1] == -128);
   assert(r[2].type == typeid(ubyte) && r[2] == 255);
   assert(r[3].type == typeid(short) && r[3] == short.min);
   assert(r[4].type == typeid(ushort) && r[4] == ushort.max);
   assert(r[5].type == typeid(int) && r[5] == 42);
   assert(r[6].type == typeid(uint) && r[6] == uint.max);
   assert(r[7].type == typeid(long) && r[7] == long.min);
   assert(r[8].type == typeid(ulong) && r[8] == ulong.max);
   assert(r[9].type == typeid(char[]) && r[9] == ['A','B','C']);
   assert(r[10].type == typeid(char[]) && r[10] == cast(char[]) "The quick brown fox");
   assert(r[11].type == typeid(ubyte[]) && r[11] == cast(ubyte[]) [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]);
   d = r[12].get!(MYSQL_DATE);
   assert(d.year == 2007 && d.month == 1 && d.day == 1);
   t = r[13].get!(MYSQL_TIMEDIFF);
   assert(t.hour == 12 && t.minute == 12 && t.second == 12);
   dt = r[14].get!(MYSQL_DATETIME);
   assert(dt.year == 2007 && dt.month == 1 && dt.day == 1 && dt.hour == 12 && dt.minute == 12 && dt.second == 12);
   assert(r[15].type == typeid(double) && r[15].toString() == to!string(1.234567890987654));
   assert(r[16].type == typeid(float) && r[16].toString() == to!string(22.4f));
   assert(!r[17].hasValue());

   TestStruct teststruct;
   teststruct.nullcol = 999;
   rs.rowToStruct(teststruct);
   assert(teststruct.bytecol == -128 && teststruct.longcol == long.min && teststruct.nullcol == 0);
   rs.close();
   // Connection tied up, so
   c3.reset();

   cleanup.execSQL(ra);
   string seq = "0123456789abcdef";

   c3.sql = "insert into basetest (intcol, stringcol) values(?, ?)";
   int m = 0;
   char[] ss;
   c3.setInBindings(m, ss);
   for (; m < 16; m++)
   {
      ss = cast(char[]) seq[0..m+1];
      c3.updateIP(ss);
      c3.execPrepared(ra);
   }
   c3.sql = "select intcol, stringcol from basetest";
   rs = c3.execSQLSequence();
   for (int i = 0;; i++)
   {
      if (rs.empty)
         break;
      Row tr = rs.front;
      assert(tr[0] == i && cast(string) tr[1].get!(char[]) == seq[0..i+1]);
      rs.popFront();
   }
   rs.close();

   rs = c3.execPreparedSequence();
   for (int i = 0;; i++)
   {
      if (rs.empty)
         break;
      Row tr = rs.front;
      assert(tr[0] == i && cast(string) tr[1].get!(char[]) == seq[0..i+1]);
      rs.popFront();
   }
   rs.close();

   // Test a result set with a chunked column and a delegate
   OutChunkDelegate trashBin(ref ulong requestedCount, ref ulong actualCount, ref ubyte[] prefix)
   {
      bool reported = false;

      // This will be the delegate. It gets passed a pointer to a buffer that will contain bx.chunkSize
      // bytes until the last chunk, which will be less than that.
      void foo(ubyte* a, uint cs, ulong ts)
      {
         if (!reported)
         {
            ubyte[] uba = cast(ubyte[]) a[0..10];
            prefix = uba[0..10].dup;
            requestedCount = ts;
            reported = true;
         }
         // check the passed buffer
         if (!(cs == 65535 || cs == 1))
            throw new Exception("Expected buffers to be 65535 or 1 length");
         if (cs == 1)
         {
            if (a[0] != 0)
               throw new Exception("Expected buffer of length 1 to contain zero byte");
         }
         else
         {
            for (int i = 0; i < 65535; i++)
            {
               if (a[i] != i%256)
                  throw new Exception("Expected buffer of length 65535 to contain cyclic values i%256");
            }
         }
         actualCount += cs;
      }

      return &foo;
   }

   ulong reported, actual;
   ubyte[] prefix;

   c3.sql = "select * from tblob limit 1";
   ChunkingSpec[] csa;
   csa ~= ChunkingSpec(1, 65535, trashBin(reported, actual, prefix));
   rs = c3.execPreparedSequence(csa);
   r = rs.front;
   assert(reported == 65535*50+1 && actual == reported && to!(string)(prefix) == "[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]");

   // This needs to come out, but it pleases me to see it ;=)
   writeln("Unit tests completed OK");
}

debug (1)
{
   void main()
   {
   }
}
