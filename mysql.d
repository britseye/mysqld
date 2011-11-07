/* Copyright (c) 2000, 2011, Oracle and/or its affiliates. All rights reserved.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; version 2 of the License.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301  USA */

/*
  This file defines the client API to MySQL and also the ABI of the
  dynamically linked libmysqlclient.

  The ABI should never be changed in a released product of MySQL,
  thus you need to take great care when changing the file. In case
  the file is changed so the ABI is broken, you must also update
  the SHARED_LIB_MAJOR_VERSION in cmake/mysql_version.cmake
*/

extern (C):

alias ubyte my_bool;
alias int my_socket;

// mysql_version.h stuff
immutable char* MYSQL_SERVER_VERSION = "5.5.16\0".ptr;
immutable char* MYSQL_BASE_VERSION = "mysqld-5.5\0".ptr;
immutable char* MYSQL_SERVER_SUFFIX_DEF = "\0".ptr;
immutable int FRM_VER = 6;
immutable int MYSQL_VERSION_ID = 50516;
immutable int MYSQL_PORT = 3306;
immutable int MYSQL_PORT_DEFAULT = 0;
immutable char* MYSQL_UNIX_ADDR = "/var/run/mysqld/mysqld.sock\0".ptr;
immutable char* MYSQL_CONFIG_NAME = "my.cnf\0".ptr;
immutable char* MYSQL_COMPILATION_COMMENT = "MySQL Community Server (GPL)\0".ptr;

immutable string LICENSE = "GPL";
// end mysql_version.h stuff


// mysql_com.h stuff
immutable int HOSTNAME_LENGTH = 60;
immutable int SYSTEM_CHARSET_MBMAXLEN = 3;
immutable int NAME_CHAR_LEN = 64;              /* Field/table name length */
immutable int USERNAME_CHAR_LENGTH = 16;
immutable int NAME_LEN = (NAME_CHAR_LEN*SYSTEM_CHARSET_MBMAXLEN);
immutable int USERNAME_LENGTH = (USERNAME_CHAR_LENGTH*SYSTEM_CHARSET_MBMAXLEN);

immutable string MYSQL_AUTODETECT_CHARSET_NAME = "auto";

immutable int SERVER_VERSION_LENGTH = 60;
immutable int SQLSTATE_LENGTH = 5;

/*
  Maximum length of comments
*/
immutable int TABLE_COMMENT_INLINE_MAXLEN = 180; /* pre 6.0: 60 characters */
immutable int TABLE_COMMENT_MAXLEN = 2048;
immutable int COLUMN_COMMENT_MAXLEN = 1024;
immutable int INDEX_COMMENT_MAXLEN = 1024;

/*
  USER_HOST_BUFF_SIZE -- length of string buffer, that is enough to contain
  username and hostname parts of the user identifier with trailing zero in
  MySQL standard format:
  user_name_part@host_name_part\0
*/
immutable int USER_HOST_BUFF_SIZE = HOSTNAME_LENGTH + USERNAME_LENGTH + 2;

immutable string LOCAL_HOST = "localhost";
immutable string LOCAL_HOST_NAMEDPIPE = ".";

//#if defined(__WIN__) && !defined( _CUSTOMCONFIG_)
//#define MYSQL_NAMEDPIPE "MySQL"
//#define MYSQL_SERVICENAME "MySQL"
//#endif /* __WIN__ */

/*
  You should add new commands to the end of this list, otherwise old
  servers won't be able to handle them as 'unsupported'.
*/

enum enum_server_command
{
  COM_SLEEP, COM_QUIT, COM_INIT_DB, COM_QUERY, COM_FIELD_LIST,
  COM_CREATE_DB, COM_DROP_DB, COM_REFRESH, COM_SHUTDOWN, COM_STATISTICS,
  COM_PROCESS_INFO, COM_CONNECT, COM_PROCESS_KILL, COM_DEBUG, COM_PING,
  COM_TIME, COM_DELAYED_INSERT, COM_CHANGE_USER, COM_BINLOG_DUMP,
  COM_TABLE_DUMP, COM_CONNECT_OUT, COM_REGISTER_SLAVE,
  COM_STMT_PREPARE, COM_STMT_EXECUTE, COM_STMT_SEND_LONG_DATA, COM_STMT_CLOSE,
  COM_STMT_RESET, COM_SET_OPTION, COM_STMT_FETCH, COM_DAEMON,
  /* don't forget to update const char *command_name[] in sql_parse.cc */

  /* Must be last */
  COM_END
}


/*
  Length of random string sent by server on handshake; this is also length of
  obfuscated password, recieved from client
*/
immutable int SCRAMBLE_LENGTH = 20;
immutable int SCRAMBLE_LENGTH_323 = 8;
/* length of password stored in the db: new passwords are preceeded with '*' */
immutable int SCRAMBLED_PASSWORD_CHAR_LENGTH = (SCRAMBLE_LENGTH*2+1);
immutable int SCRAMBLED_PASSWORD_CHAR_LENGTH_323 = (SCRAMBLE_LENGTH_323*2);


immutable int NOT_NULL_FLAG =	1;		/* Field can't be NULL */
immutable int PRI_KEY_FLAG	= 2;		/* Field is part of a primary key */
immutable int UNIQUE_KEY_FLAG = 4;		/* Field is part of a unique key */
immutable int MULTIPLE_KEY_FLAG = 8;		/* Field is part of a key */
immutable int BLOB_FLAG	= 16;		/* Field is a blob */
immutable int UNSIGNED_FLAG = 32;		/* Field is unsigned */
immutable int ZEROFILL_FLAG = 64;		/* Field is zerofill */
immutable int BINARY_FLAG = 128;		/* Field is binary   */

/* The following are only sent to new clients */
immutable int ENUM_FLAG = 256;		/* field is an enum */
immutable int AUTO_INCREMENT_FLAG = 512;		/* field is a autoincrement field */
immutable int TIMESTAMP_FLAG = 1024;		/* Field is a timestamp */
immutable int SET_FLAG = 2048;		/* field is a set */
immutable int NO_DEFAULT_VALUE_FLAG = 4096;	/* Field doesn't have default value */
immutable int ON_UPDATE_NOW_FLAG = 8192;         /* Field is set to NOW on UPDATE */
immutable int NUM_FLAG = 32768;		/* Field is num (for clients) */
immutable int PART_KEY_FLAG = 16384;		/* Intern; Part of some key */
immutable int GROUP_FLAG = 32768;		/* Intern: Group field */
immutable int UNIQUE_FLAG = 65536;		/* Intern: Used by sql_yacc */
immutable int BINCMP_FLAG = 131072;		/* Intern: Used by sql_yacc */
immutable int GET_FIXED_FIELDS_FLAG = (1 << 18); /* Used to get fields in item tree */
immutable int FIELD_IN_PART_FUNC_FLAG = (1 << 19);/* Field part of partition func */
immutable int FIELD_IN_ADD_INDEX = (1 << 20);	/* Intern: Field used in ADD INDEX */
immutable int FIELD_IS_RENAMED = (1<< 21);       /* Intern: Field is being renamed */
immutable int FIELD_FLAGS_STORAGE_MEDIA = 22;    /* Field storage media, bit 22-23,
                                           reserved by MySQL Cluster */
immutable int FIELD_FLAGS_COLUMN_FORMAT = 24;    /* Field column format, bit 24-25,
                                           reserved by MySQL Cluster */

immutable int REFRESH_GRANT = 1;	/* Refresh grant tables */
immutable int REFRESH_LOG = 2;	/* Start on new log file */
immutable int REFRESH_TABLES = 4;	/* close all tables */
immutable int REFRESH_HOSTS = 8;	/* Flush host cache */
immutable int REFRESH_STATUS = 16;	/* Flush status variables */
immutable int REFRESH_THREADS = 32;	/* Flush thread cache */
immutable int REFRESH_SLAVE = 64;      /* Reset master info and restart slave
					   thread */
immutable int REFRESH_MASTER = 128;     /* Remove all bin logs in the index
					   and truncate the index */
immutable int REFRESH_ERROR_LOG = 256; /* Rotate only the erorr log */
immutable int REFRESH_ENGINE_LOG = 512; /* Flush all storage engine logs */
immutable int REFRESH_BINARY_LOG = 1024; /* Flush the binary log */
immutable int REFRESH_RELAY_LOG = 2048; /* Flush the relay log */
immutable int REFRESH_GENERAL_LOG = 4096; /* Flush the general log */
immutable int REFRESH_SLOW_LOG = 8192; /* Flush the slow query log */

/* The following can't be set with mysql_refresh() */
immutable int REFRESH_READ_LOCK = 16384;	/* Lock tables for read */
immutable int REFRESH_FAST = 32768;	/* Intern flag */

/* RESET (remove all queries) from query cache */
immutable int REFRESH_QUERY_CACHE = 65536;
immutable int REFRESH_QUERY_CACHE_FREE = 0x20000; /* pack query cache */
immutable int REFRESH_DES_KEY_FILE = 0x40000;
immutable int REFRESH_USER_RESOURCES = 0x80000;

immutable int CLIENT_LONG_PASSWORD = 1;	/* new more secure passwords */
immutable int CLIENT_FOUND_ROWS = 2;	/* Found instead of affected rows */
immutable int CLIENT_LONG_FLAG = 4;	/* Get all column flags */
immutable int CLIENT_CONNECT_WITH_DB = 8;	/* One can specify db on connect */
immutable int CLIENT_NO_SCHEMA = 16;	/* Don't allow database.table.column */
immutable int CLIENT_COMPRESS = 32;	/* Can use compression protocol */
immutable int CLIENT_ODBC = 64;	/* Odbc client */
immutable int CLIENT_LOCAL_FILES = 128;	/* Can use LOAD DATA LOCAL */
immutable int CLIENT_IGNORE_SPACE = 256;	/* Ignore spaces before '(' */
immutable int CLIENT_PROTOCOL_41 = 512;	/* New 4.1 protocol */
immutable int CLIENT_INTERACTIVE = 1024;	/* This is an interactive client */
immutable int CLIENT_SSL = 2048;	/* Switch to SSL after handshake */
immutable int CLIENT_IGNORE_SIGPIPE = 4096;    /* IGNORE sigpipes */
immutable int CLIENT_TRANSACTIONS = 8192;	/* Client knows about transactions */
immutable int CLIENT_RESERVED = 16384;   /* Old flag for 4.1 protocol  */
immutable int CLIENT_SECURE_CONNECTION = 32768;  /* New 4.1 authentication */
immutable int CLIENT_MULTI_STATEMENTS = (1 << 16); /* Enable/disable multi-stmt support */
immutable int CLIENT_MULTI_RESULTS = (1 << 17); /* Enable/disable multi-results */
immutable int CLIENT_PS_MULTI_RESULTS = (1 << 18); /* Multi-results in PS-protocol */

immutable int CLIENT_PLUGIN_AUTH = (1 << 19); /* Client supports plugin authentication */

immutable int CLIENT_SSL_VERIFY_SERVER_CERT = (1 << 30);
immutable int CLIENT_REMEMBER_OPTIONS = (1 << 31);

// Don't know what to do here
/*
#ifdef HAVE_COMPRESS
#define CAN_CLIENT_COMPRESS CLIENT_COMPRESS
#else
#define CAN_CLIENT_COMPRESS 0
#endif
*/
immutable bool HAVE_COMPRESS = false;
int CAN_CLIENT_COMPRESS() { return HAVE_COMPRESS? CLIENT_COMPRESS: 0; }

/* Gather all possible capabilites (flags) supported by the server */
immutable int CLIENT_ALL_FLAGS  = (CLIENT_LONG_PASSWORD |
                           CLIENT_FOUND_ROWS |
                           CLIENT_LONG_FLAG |
                           CLIENT_CONNECT_WITH_DB |
                           CLIENT_NO_SCHEMA |
                           CLIENT_COMPRESS |
                           CLIENT_ODBC |
                           CLIENT_LOCAL_FILES |
                           CLIENT_IGNORE_SPACE |
                           CLIENT_PROTOCOL_41 |
                           CLIENT_INTERACTIVE |
                           CLIENT_SSL |
                           CLIENT_IGNORE_SIGPIPE |
                           CLIENT_TRANSACTIONS |
                           CLIENT_RESERVED |
                           CLIENT_SECURE_CONNECTION |
                           CLIENT_MULTI_STATEMENTS |
                           CLIENT_MULTI_RESULTS |
                           CLIENT_PS_MULTI_RESULTS |
                           CLIENT_SSL_VERIFY_SERVER_CERT |
                           CLIENT_REMEMBER_OPTIONS |
                           CLIENT_PLUGIN_AUTH);

/*
  Switch off the flags that are optional and depending on build flags
  If any of the optional flags is supported by the build it will be switched
  on before sending to the client during the connection handshake.
*/
immutable int CLIENT_BASIC_FLAGS = (((CLIENT_ALL_FLAGS & ~CLIENT_SSL)
                                               & ~CLIENT_COMPRESS)
                                               & ~CLIENT_SSL_VERIFY_SERVER_CERT);

/**
  Is raised when a multi-statement transaction
  has been started, either explicitly, by means
  of BEGIN or COMMIT AND CHAIN, or
  implicitly, by the first transactional
  statement, when autocommit=off.
*/
immutable int SERVER_STATUS_IN_TRANS = 1;
immutable int SERVER_STATUS_AUTOCOMMIT = 2;	/* Server in auto_commit mode */
immutable int SERVER_MORE_RESULTS_EXISTS = 8;    /* Multi query - next query exists */
immutable int SERVER_QUERY_NO_GOOD_INDEX_USED = 16;
immutable int SERVER_QUERY_NO_INDEX_USED = 32;
/**
  The server was able to fulfill the clients request and opened a
  read-only non-scrollable cursor for a query. This flag comes
  in reply to COM_STMT_EXECUTE and COM_STMT_FETCH commands.
*/
immutable int SERVER_STATUS_CURSOR_EXISTS = 64;
/**
  This flag is sent when a read-only cursor is exhausted, in reply to
  COM_STMT_FETCH command.
*/
immutable int SERVER_STATUS_LAST_ROW_SENT = 128;
immutable int SERVER_STATUS_DB_DROPPED = 256; /* A database was dropped */
immutable int SERVER_STATUS_NO_BACKSLASH_ESCAPES = 512;
/**
  Sent to the client if after a prepared statement reprepare
  we discovered that the new statement returns a different
  number of result set columns.
*/
immutable int SERVER_STATUS_METADATA_CHANGED = 1024;
immutable int SERVER_QUERY_WAS_SLOW = 2048;

/**
  To mark ResultSet containing output parameter values.
*/
immutable int SERVER_PS_OUT_PARAMS = 4096;

/**
  Server status flags that must be cleared when starting
  execution of a new SQL statement.
  Flags from this set are only added to the
  current server status by the execution engine, but
  never removed -- the execution engine expects them
  to disappear automagically by the next command.
*/
immutable int SERVER_STATUS_CLEAR_SET = (SERVER_QUERY_NO_GOOD_INDEX_USED|
                                 SERVER_QUERY_NO_INDEX_USED|
                                 SERVER_MORE_RESULTS_EXISTS|
                                 SERVER_STATUS_METADATA_CHANGED |
                                 SERVER_QUERY_WAS_SLOW |
                                 SERVER_STATUS_DB_DROPPED |
                                 SERVER_STATUS_CURSOR_EXISTS|
                                 SERVER_STATUS_LAST_ROW_SENT);

immutable int MYSQL_ERRMSG_SIZE = 512;
immutable int NET_READ_TIMEOUT = 30;		/* Timeout on read */
immutable int NET_WRITE_TIMEOUT = 60;		/* Timeout on write */
immutable int NET_WAIT_TIMEOUT = 8*60*60;		/* Wait for new query */

immutable int ONLY_KILL_QUERY = 1;


struct st_vio;					/* Only C */
alias st_vio Vio;

immutable int MAX_TINYINT_WIDTH = 3;       /* Max width for a TINY w.o. sign */
immutable int MAX_SMALLINT_WIDTH = 5;       /* Max width for a SHORT w.o. sign */
immutable int MAX_MEDIUMINT_WIDTH = 8;       /* Max width for a INT24 w.o. sign */
immutable int MAX_INT_WIDTH = 10;      /* Max width for a LONG w.o. sign */
immutable int MAX_BIGINT_WIDTH = 20;      /* Max width for a LONGLONG */
immutable int MAX_CHAR_WIDTH = 255;	/* Max length for a CHAR colum */
immutable int MAX_BLOB_WIDTH = 16777216;	/* Default width for blob */

struct st_net {
  Vio *vio;
  ubyte* buff, buff_end, write_pos, read_pos;
  my_socket fd;					/* For Perl DBI/dbd */
  /*
    The following variable is set if we are doing several queries in one
    command ( as in LOAD TABLE ... FROM MASTER ),
    and do not want to confuse the client with OK at the wrong time
  */
  uint remain_in_buf,length, buf_length, where_b;
  uint max_packet,max_packet_size;
  uint pkt_nr,compress_pkt_nr;
  uint write_timeout, read_timeout, retry_count;
  int fcntl;
  uint *return_status;
  ubyte reading_or_writing;
  char save_char;
  my_bool unused1; /* Please remove with the next incompatible ABI change. */
  my_bool unused2; /* Please remove with the next incompatible ABI change */
  my_bool compress;
  my_bool unused3; /* Please remove with the next incompatible ABI change. */
  /*
    Pointer to query object in query cache, do not equal NULL (0) for
    queries in cache that have not stored its results yet
  */
  /*
    Unused, please remove with the next incompatible ABI change.
  */
  ubyte* unused;
  uint last_errno;
  ubyte error;
  my_bool unused4; /* Please remove with the next incompatible ABI change. */
  my_bool unused5; /* Please remove with the next incompatible ABI change. */
  /** Client library error message buffer. Actually belongs to struct MYSQL. */
  char last_error[MYSQL_ERRMSG_SIZE];
  /** Client library sqlstate buffer. Set along with the error message. */
  char sqlstate[SQLSTATE_LENGTH+1];
  void* extension;
}
alias st_net NET;

immutable uint packet_error = (~(cast(uint) 0));

enum enum_field_types { MYSQL_TYPE_DECIMAL, MYSQL_TYPE_TINY,
			MYSQL_TYPE_SHORT,  MYSQL_TYPE_LONG,
			MYSQL_TYPE_FLOAT,  MYSQL_TYPE_DOUBLE,
			MYSQL_TYPE_NULL,   MYSQL_TYPE_TIMESTAMP,
			MYSQL_TYPE_LONGLONG,MYSQL_TYPE_INT24,
			MYSQL_TYPE_DATE,   MYSQL_TYPE_TIME,
			MYSQL_TYPE_DATETIME, MYSQL_TYPE_YEAR,
			MYSQL_TYPE_NEWDATE, MYSQL_TYPE_VARCHAR,
			MYSQL_TYPE_BIT,
                        MYSQL_TYPE_NEWDECIMAL=246,
			MYSQL_TYPE_ENUM=247,
			MYSQL_TYPE_SET=248,
			MYSQL_TYPE_TINY_BLOB=249,
			MYSQL_TYPE_MEDIUM_BLOB=250,
			MYSQL_TYPE_LONG_BLOB=251,
			MYSQL_TYPE_BLOB=252,
			MYSQL_TYPE_VAR_STRING=253,
			MYSQL_TYPE_STRING=254,
			MYSQL_TYPE_GEOMETRY=255

}

/* For backward compatibility */
/*
#define CLIENT_MULTI_QUERIES    CLIENT_MULTI_STATEMENTS
#define FIELD_TYPE_DECIMAL     MYSQL_TYPE_DECIMAL
#define FIELD_TYPE_NEWDECIMAL  MYSQL_TYPE_NEWDECIMAL
#define FIELD_TYPE_TINY        MYSQL_TYPE_TINY
#define FIELD_TYPE_SHORT       MYSQL_TYPE_SHORT
#define FIELD_TYPE_LONG        MYSQL_TYPE_LONG
#define FIELD_TYPE_FLOAT       MYSQL_TYPE_FLOAT
#define FIELD_TYPE_DOUBLE      MYSQL_TYPE_DOUBLE
#define FIELD_TYPE_NULL        MYSQL_TYPE_NULL
#define FIELD_TYPE_TIMESTAMP   MYSQL_TYPE_TIMESTAMP
#define FIELD_TYPE_LONGLONG    MYSQL_TYPE_LONGLONG
#define FIELD_TYPE_INT24       MYSQL_TYPE_INT24
#define FIELD_TYPE_DATE        MYSQL_TYPE_DATE
#define FIELD_TYPE_TIME        MYSQL_TYPE_TIME
#define FIELD_TYPE_DATETIME    MYSQL_TYPE_DATETIME
#define FIELD_TYPE_YEAR        MYSQL_TYPE_YEAR
#define FIELD_TYPE_NEWDATE     MYSQL_TYPE_NEWDATE
#define FIELD_TYPE_ENUM        MYSQL_TYPE_ENUM
#define FIELD_TYPE_SET         MYSQL_TYPE_SET
#define FIELD_TYPE_TINY_BLOB   MYSQL_TYPE_TINY_BLOB
#define FIELD_TYPE_MEDIUM_BLOB MYSQL_TYPE_MEDIUM_BLOB
#define FIELD_TYPE_LONG_BLOB   MYSQL_TYPE_LONG_BLOB
#define FIELD_TYPE_BLOB        MYSQL_TYPE_BLOB
#define FIELD_TYPE_VAR_STRING  MYSQL_TYPE_VAR_STRING
#define FIELD_TYPE_STRING      MYSQL_TYPE_STRING
#define FIELD_TYPE_CHAR        MYSQL_TYPE_TINY
#define FIELD_TYPE_INTERVAL    MYSQL_TYPE_ENUM
#define FIELD_TYPE_GEOMETRY    MYSQL_TYPE_GEOMETRY
#define FIELD_TYPE_BIT         MYSQL_TYPE_BIT
*/

/* Shutdown/kill enums and constants */

/* Bits for THD::killable. */
immutable ubyte MYSQL_SHUTDOWN_KILLABLE_CONNECT = cast(ubyte)(1 << 0);
immutable ubyte MYSQL_SHUTDOWN_KILLABLE_TRANS     = cast(ubyte)(1 << 1);
immutable ubyte MYSQL_SHUTDOWN_KILLABLE_LOCK_TABLE = cast(ubyte)(1 << 2);
immutable ubyte MYSQL_SHUTDOWN_KILLABLE_UPDATE     = cast(ubyte)(1 << 3);

enum mysql_enum_shutdown_level {
  /*
    We want levels to be in growing order of hardness (because we use number
    comparisons). Note that DEFAULT does not respect the growing property, but
    it's ok.
  */
  SHUTDOWN_DEFAULT = 0,
  /* wait for existing connections to finish */
  SHUTDOWN_WAIT_CONNECTIONS= MYSQL_SHUTDOWN_KILLABLE_CONNECT,
  /* wait for existing trans to finish */
  SHUTDOWN_WAIT_TRANSACTIONS= MYSQL_SHUTDOWN_KILLABLE_TRANS,
  /* wait for existing updates to finish (=> no partial MyISAM update) */
  SHUTDOWN_WAIT_UPDATES= MYSQL_SHUTDOWN_KILLABLE_UPDATE,
  /* flush InnoDB buffers and other storage engines' buffers*/
  SHUTDOWN_WAIT_ALL_BUFFERS= (MYSQL_SHUTDOWN_KILLABLE_UPDATE << 1),
  /* don't flush InnoDB buffers, flush other storage engines' buffers*/
  SHUTDOWN_WAIT_CRITICAL_BUFFERS= (MYSQL_SHUTDOWN_KILLABLE_UPDATE << 1) + 1,
  /* Now the 2 levels of the KILL command */
  KILL_QUERY= 254,
  KILL_CONNECTION= 255
}


enum enum_cursor_type
{
  CURSOR_TYPE_NO_CURSOR= 0,
  CURSOR_TYPE_READ_ONLY= 1,
  CURSOR_TYPE_FOR_UPDATE= 2,
  CURSOR_TYPE_SCROLLABLE= 4
}


/* options for mysql_set_option */
enum enum_mysql_set_option
{
  MYSQL_OPTION_MULTI_STATEMENTS_ON,
  MYSQL_OPTION_MULTI_STATEMENTS_OFF
}

void net_new_transaction(NET* net) { net.pkt_nr = 0; }

my_bool	my_net_init(NET* net, Vio* vio);
void	my_net_local_init(NET* net);
void	net_end(NET* net);
void	net_clear(NET* net, my_bool clear_buffer);
my_bool net_realloc(NET* net, size_t length);
my_bool	net_flush(NET* net);
my_bool	my_net_write(NET* net,const ubyte* packet, size_t len);
my_bool	net_write_command(NET* net, ubyte command,
			  const ubyte* header, size_t head_len,
			  const ubyte* packet, size_t len);
int	net_real_write(NET* net,const ubyte* packet, size_t len);
uint my_net_read(NET* net);

void my_net_set_write_timeout(NET *net, uint timeout);
void my_net_set_read_timeout(NET *net, uint timeout);

struct sockaddr;
int my_connect(my_socket s, const sockaddr* name, uint namelen, uint timeout);

struct rand_struct {
  uint seed1,seed2,max_value;
  double max_value_dbl;
}

  /* The following is for user defined functions */

enum Item_result {STRING_RESULT=0, REAL_RESULT, INT_RESULT, ROW_RESULT,
                  DECIMAL_RESULT}

struct st_udf_args
{
  uint arg_count;		/* Number of arguments */
  Item_result* arg_type;		/* Pointer to item_results */
  char** args;				/* Pointer to argument */
  uint* lengths;		/* Length of string arguments */
  char* maybe_null;			/* Set to 1 for all maybe_null args */
  char** attributes;                    /* Pointer to attribute name */
  uint* attribute_lengths;     /* Length of attribute arguments */
  void* extension;
}
alias st_udf_args UDF_ARGS;
  /* This holds information about the result */

struct st_udf_init
{
  my_bool maybe_null;          /* 1 if function can return NULL */
  uint decimals;       /* for real functions */
  uint max_length;    /* For string functions */
  char* ptr;                   /* free pointer for function data */
  my_bool const_item;          /* 1 if function always returns the same value */
  void* extension;
}
alias st_udf_init UDF_INIT;
/*
  TODO: add a notion for determinism of the UDF.
  See Item_udf_func::update_used_tables ()
*/

  /* Constants when using compression */
immutable int NET_HEADER_SIZE = 4;		/* standard header size */
immutable int COMP_HEADER_SIZE = 3;		/* compression header extra size */

  /* Prototypes to password functions */

/*
  These functions are used for authentication by client and server and
  implemented in sql/password.c
*/

void randominit(rand_struct*, uint seed1, uint seed2);
double my_rnd(rand_struct*);
void create_random_string(char* to, uint length, rand_struct* rand_st);

void hash_password(uint* to, const char* password, uint password_len);
void make_scrambled_password_323(char* to, const char* password);
void scramble_323(char* to, const char* message, const char* password);
my_bool check_scramble_323(const ubyte* reply, const char* message,
                           uint *salt);
void get_salt_from_password_323(uint* res, const char* password);
void make_password_from_salt_323(char *to, const uint* salt);

void make_scrambled_password(char *to, const char* password);
void scramble(char *to, const char* message, const char* password);
my_bool check_scramble(const ubyte* reply, const char* message,
                       const ubyte* hash_stage2);
void get_salt_from_password(ubyte* res, const char* password);
void make_password_from_salt(char* to, const ubyte* hash_stage2);
char* octet2hex(char* to, const char* str, uint len);

/* end of password.c */

char* get_tty_password(const char* opt_message);
const(char*) mysql_errno_to_sqlstate(uint mysql_errno);

/* Some other useful functions */

my_bool my_thread_init();
void my_thread_end();

uint net_field_length(ubyte** packet);
my_ulonglong net_field_length_ll(ubyte** packet);
ubyte* net_store_length(ubyte* pkg, ulong length);

immutable uint NULL_LENGTH = 0; /* For net_store_length */
immutable int MYSQL_STMT_HEADER = 4;
immutable int MYSQL_LONG_DATA_HEADER  = 6;

immutable int NOT_FIXED_DEC = 31;
// end mysql_com.h stuff


// mysql_time.h stuff
/*
  Time declarations shared between the server and client API:
  you should not add anything to this header unless it's used
  (and hence should be visible) in mysql.h.
  If you're looking for a place to add new time-related declaration,
  it's most likely my_time.h. See also "C API Handling of Date
  and Time Values" chapter in documentation.
*/

enum enum_mysql_timestamp_type
{
  MYSQL_TIMESTAMP_NONE= -2, MYSQL_TIMESTAMP_ERROR= -1,
  MYSQL_TIMESTAMP_DATE= 0, MYSQL_TIMESTAMP_DATETIME= 1, MYSQL_TIMESTAMP_TIME= 2
}


/*
  Structure which is used to represent datetime values inside MySQL.

  We assume that values in this structure are normalized, i.e. year <= 9999,
  month <= 12, day <= 31, hour <= 23, hour <= 59, hour <= 59. Many functions
  in server such as my_system_gmt_sec() or make_time() family of functions
  rely on this (actually now usage of make_*() family relies on a bit weaker
  restriction). Also functions that produce MYSQL_TIME as result ensure this.
  There is one exception to this rule though if this structure holds time
  value (time_type == MYSQL_TIMESTAMP_TIME) days and hour member can hold
  bigger values.
*/
struct st_mysql_time
{
  uint  year, month, day, hour, minute, second;
  uint second_part;
  my_bool       neg;
  enum_mysql_timestamp_type time_type;
}

// The same struct is used for a number of column type in MySQL, so to
// properly distinguish these types when they must be bound to D variables
// separate typedefs are used.
alias st_mysql_time MYSQL_TIME;
typedef st_mysql_time MYSQL_DATE;
typedef st_mysql_time MYSQL_DATETIME;
typedef st_mysql_time MYSQL_TIMESTAMP;
typedef st_mysql_time MYSQL_TIMEDIFF;
// end mysql_time.h stuff

// my_list.h stuff
struct st_list
{
  st_list* prev, next;
  void* data;
}
alias st_list LIST;

typedef int function(void*, void*) list_walk_action;

LIST* list_add(LIST* root, LIST* element);
LIST* list_delete(LIST* root,LIST* element);
LIST* list_cons(void* data, LIST* root);
LIST* list_reverse(LIST* root);
void list_free(LIST* root, uint free_data);
uint list_length(LIST*);
int list_walk(LIST*, int action, ubyte* argument);

LIST* list_rest(LIST* a) { return a.next; }
LIST* list_push(LIST* a, void* b) { return list_cons(b, a); }
void my_free(void *ptr);
void list_pop(LIST* A) { LIST* old=A; A=list_delete(old, old); my_free(old); }
// end my_list.h stuff

extern uint mysql_port;
extern char* mysql_unix_port;

immutable uint CLIENT_NET_READ_TIMEOUT = 365*24*3600;	/* Timeout on read */
immutable uint CLIENT_NET_WRITE_TIMEOUT = 365*24*3600;	/* Timeout on write */

bool IS_PRI_KEY(int n) { return ((n & PRI_KEY_FLAG) != 0); }
bool IS_NOT_NULL(int n) { return ((n & NOT_NULL_FLAG) != 0); }
bool IS_BLOB(int n) { return ((n & BLOB_FLAG) != 0); }
/**
   Returns true if the value is a number which does not need quotes for
   the sql_lex.cc parser to parse correctly.
*/
bool IS_NUM(int t)	{ return ((t <= enum_field_types.MYSQL_TYPE_INT24 && t != enum_field_types.MYSQL_TYPE_TIMESTAMP) ||
                                t == enum_field_types.MYSQL_TYPE_YEAR || t == enum_field_types.MYSQL_TYPE_NEWDECIMAL); }
bool IS_LONGDATA(int t) { return (t >= enum_field_types.MYSQL_TYPE_TINY_BLOB && t <= enum_field_types.MYSQL_TYPE_STRING); }


struct MYSQL_FIELD
{
  char *name;                 /* Name of column */
  char *org_name;             /* Original column name, if an alias */
  char *table;                /* Table of column if column was a field */
  char *org_table;            /* Org table name, if table was an alias */
  char *db;                   /* Database for table */
  char *catalog;	      /* Catalog for table */
  char *def;                  /* Default value (set by mysql_list_fields) */
  uint length;       /* Width of column (create length) */
  uint max_length;   /* Max width for selected set */
  uint name_length;
  uint org_name_length;
  uint table_length;
  uint org_table_length;
  uint db_length;
  uint catalog_length;
  uint def_length;
  uint flags;         /* Div flags */
  uint decimals;      /* Number of decimals in field */
  uint charsetnr;     /* Character set */
  enum_field_types type; /* Type of field. See mysql_com.h for types */
  void *extension;
}

alias char** MYSQL_ROW;		/* return data as array of strings */
alias uint MYSQL_FIELD_OFFSET; /* offset to current field */

alias ulong my_ulonglong;

// my_alloc.h stuff
struct st_used_mem
{				   /* struct for once_alloc (block) */
  st_used_mem* next;	   /* Next block in use */
  uint	left;		   /* memory left in block  */
  uint	size;		   /* size of block */
}
alias st_used_mem USED_MEM;


struct st_mem_root
{
  USED_MEM *free;                  /* blocks with free memory in it */
  USED_MEM *used;                  /* blocks almost without free memory */
  USED_MEM *pre_alloc;             /* preallocated block */
  /* if block have less memory it will be put in 'used' list */
  size_t min_malloc;
  size_t block_size;               /* initial block size */
  uint block_num;          /* allocated blocks counter */
  /*
     first free block in queue test counter (if it exceed
     MAX_BLOCK_USAGE_BEFORE_DROP block will be dropped in 'used' list)
  */
  uint first_block_usage;

  void function() error_handler;
}
alias st_mem_root MEM_ROOT;
// end my_alloc.h stuff

// typelib.h stuff
struct st_typelib {	/* Different types saved here */
  uint count;		/* How many types */
  const char* name;		/* Name of typelib */
  const char** type_names;
  uint* type_lengths;
}
alias st_typelib TYPELIB;

my_ulonglong find_typeset(char* x, TYPELIB* typelib, int* error_position);
int find_type_or_exit(const char* x, TYPELIB* typelib,
                             const char* option);
immutable int FIND_TYPE_BASIC = 0;
/** makes @c find_type() require the whole name, no prefix */
immutable int FIND_TYPE_NO_PREFIX = (1 << 0);
/** always implicitely on, so unused, but old code may pass it */
immutable int FIND_TYPE_NO_OVERWRITE = (1 << 1);
/** makes @c find_type() accept a number */
immutable int FIND_TYPE_ALLOW_NUMBER = (1 << 2);
/** makes @c find_type() treat ',' as terminator */
immutable int FIND_TYPE_COMMA_TERM = (1 << 3);

int find_type(const char* x, const TYPELIB* typelib, uint flags);
void make_type(char* to, uint nr, TYPELIB* typelib);
const(char*) get_type(TYPELIB* typelib, uint nr);
TYPELIB* copy_typelib(MEM_ROOT* root, TYPELIB* from);

extern __gshared TYPELIB sql_protocol_typelib;

my_ulonglong find_set_from_flags(const TYPELIB* lib, uint default_name,
                              my_ulonglong cur_set, my_ulonglong default_set,
                              const char* str, uint length,
                              char** err_pos, uint *err_len);
// end typrlib.h stuff

immutable ulong MYSQL_COUNT_ERROR = ~(cast(ulong) 0);

struct MYSQL_ROWS
{
  MYSQL_ROWS* next;		/* list of rows */
  MYSQL_ROW data;
  uint length;
}

alias MYSQL_ROWS* MYSQL_ROW_OFFSET;	/* offset to current row */


//alias embedded_query_result EMBEDDED_QUERY_RESULT;
struct st_mysql_data
{
  MYSQL_ROWS* data;
  void* embedded_info;
  MEM_ROOT alloc;
  my_ulonglong rows;
  uint fields;
  /* extra info for embedded library */
  void* extension;
}
alias st_mysql_data MYSQL_DATA;

enum mysql_option
{
  MYSQL_OPT_CONNECT_TIMEOUT, MYSQL_OPT_COMPRESS, MYSQL_OPT_NAMED_PIPE,
  MYSQL_INIT_COMMAND, MYSQL_READ_DEFAULT_FILE, MYSQL_READ_DEFAULT_GROUP,
  MYSQL_SET_CHARSET_DIR, MYSQL_SET_CHARSET_NAME, MYSQL_OPT_LOCAL_INFILE,
  MYSQL_OPT_PROTOCOL, MYSQL_SHARED_MEMORY_BASE_NAME, MYSQL_OPT_READ_TIMEOUT,
  MYSQL_OPT_WRITE_TIMEOUT, MYSQL_OPT_USE_RESULT,
  MYSQL_OPT_USE_REMOTE_CONNECTION, MYSQL_OPT_USE_EMBEDDED_CONNECTION,
  MYSQL_OPT_GUESS_CONNECTION, MYSQL_SET_CLIENT_IP, MYSQL_SECURE_AUTH,
  MYSQL_REPORT_DATA_TRUNCATION, MYSQL_OPT_RECONNECT,
  MYSQL_OPT_SSL_VERIFY_SERVER_CERT, MYSQL_PLUGIN_DIR, MYSQL_DEFAULT_AUTH
}

/**
  @todo remove the "extension", move st_mysql_options completely
  out of mysql.h
*/
struct st_mysql_options_extention {
  char* plugin_dir;
  char* default_auth;
}

struct st_dynamic_array
{
  ubyte *buffer;
  uint elements,max_element;
  uint alloc_increment;
  uint size_of_element;
}
alias st_dynamic_array DYNAMIC_ARRAY;

struct st_mysql_options
{
  uint connect_timeout, read_timeout, write_timeout;
  uint port, protocol;
  uint client_flag;
  char* host;
  char* user;
  char* password;
  char* unix_socket;
  char* db;
  st_dynamic_array* init_commands;
  char *my_cnf_file;
  char* my_cnf_group;
  char* charset_dir;
  char* charset_name;
  char* ssl_key;				/* PEM key file */
  char* ssl_cert;				/* PEM cert file */
  char* ssl_ca;					/* PEM CA file */
  char* ssl_capath;				/* PEM directory of CA-s? */
  char* ssl_cipher;				/* cipher to use */
  char* shared_memory_base_name;
  uint max_allowed_packet;
  my_bool use_ssl;				/* if to use SSL or not */
  my_bool compress, named_pipe;
  my_bool unused1;
  my_bool unused2;
  my_bool unused3;
  my_bool unused4;
  mysql_option methods_to_use;
  char* client_ip;
  /* Refuse client connecting to server if it uses old (pre-4.1.1) protocol */
  my_bool secure_auth;
  /* 0 - never report, 1 - always report (default) */
  my_bool report_data_truncation;

  /* function pointers for local infile support */
  int function(void**, const char*, void*) local_infile_init;
  int function(void*, char*, uint) local_infile_read;
  void function(void*) local_infile_end;
  int function(void*, char*, uint) local_infile_error;
  void* local_infile_userdata;
  st_mysql_options_extention *extension;
}

enum mysql_status
{
  MYSQL_STATUS_READY, MYSQL_STATUS_GET_RESULT, MYSQL_STATUS_USE_RESULT,
  MYSQL_STATUS_STATEMENT_GET_RESULT
}

enum mysql_protocol_type
{
  MYSQL_PROTOCOL_DEFAULT, MYSQL_PROTOCOL_TCP, MYSQL_PROTOCOL_SOCKET,
  MYSQL_PROTOCOL_PIPE, MYSQL_PROTOCOL_MEMORY
}

struct MY_CHARSET_INFO
{
  uint number;     /* character set number              */
  uint state;      /* character set state               */
  const char* csname;    /* collation name                    */
  const char* name;      /* character set name                */
  const char* comment;   /* comment                           */
  const char* dir;       /* character set directory           */
  uint      mbminlen;   /* min. length for multibyte strings */
  uint      mbmaxlen;   /* max. length for multibyte strings */
}

struct st_mysql_methods;

struct MYSQL
{
  NET		net;			/* Communication parameters */
  ubyte* connector_fd;		/* ConnectorFd for SSL */
  char* host;
  char* user;
  char* passwd;
  char* unix_socket;
  char* server_version;
  char* host_info;
  char  *info;
  char* db;
  MY_CHARSET_INFO* charset;
  MYSQL_FIELD* fields;
  MEM_ROOT field_alloc;
  my_ulonglong affected_rows;
  my_ulonglong insert_id;		/* id if insert on table with NEXTNR */
  my_ulonglong extra_info;		/* Not used */
  uint thread_id;		/* Id for connection in server */
  uint packet_length;
  uint port;
  uint client_flag,server_capabilities;
  uint protocol_version;
  uint field_count;
  uint  server_status;
  uint server_language;
  uint warning_count;
  st_mysql_options options;
  mysql_status status;
  my_bool	free_me;		/* If free in mysql_close */
  my_bool	reconnect;		/* set to 1 if automatic reconnect */

  /* session-wide random string */
  char[SCRAMBLE_LENGTH+1] scramble;
  my_bool unused1;
  void* unused2;
  void* unused3;
  void* unused4;
  void* unused5;

  LIST* stmts;                     /* list of all statements */
  const st_mysql_methods *methods;
  void* thd;
  /*
    Points to boolean flag in MYSQL_RES  or MYSQL_STMT. We set this flag
    from mysql_stmt_close if close had to cancel result set of this object.
  */
  my_bool* unbuffered_fetch_owner;
  /* needed for embedded server - no net buffer to store the 'info' */
  char* info_buffer;
  void* extension;
}


struct MYSQL_RES
{
  my_ulonglong  row_count;
  MYSQL_FIELD* fields;
  MYSQL_DATA* data;
  MYSQL_ROWS* data_cursor;
  uint* lengths;		/* column lengths of current row */
  MYSQL* handle;		/* for unbuffered reads */
  const st_mysql_methods* methods;
  MYSQL_ROW	row;			/* If unbuffered read */
  MYSQL_ROW	current_row;		/* buffer to current row */
  MEM_ROOT	field_alloc;
  uint	field_count, current_field;
  my_bool	eof;			/* Used by mysql_fetch_row */
  /* mysql_stmt_close() had to cancel this result */
  my_bool       unbuffered_fetch_cancelled;
  void* extension;
}

/* ?????
#if !defined(MYSQL_SERVER) && !defined(MYSQL_CLIENT)
#define MYSQL_CLIENT
#endif
*/

struct MYSQL_PARAMETERS
{
  uint* p_max_allowed_packet;
  uint* p_net_buffer_length;
  void* extension;
}


/*
  Set up and bring down the server; to ensure that applications will
  work when linked against either the standard client library or the
  embedded server library, these functions should be called.
*/
int mysql_server_init(int argc, char** argv, char** groups);
void mysql_server_end();

/*
  mysql_server_init/end need to be called when using libmysqld or
  libmysqlclient (exactly, mysql_server_init() is called by mysql_init() so
  you don't need to call it explicitely; but you need to call
  mysql_server_end() to free memory). The names are a bit misleading
  (mysql_SERVER* to be used when using libmysqlCLIENT). So we add more general
  names which suit well whether you're using libmysqld or libmysqlclient. We
  intend to promote these aliases over the mysql_server* ones.
*/
int mysql_library_init(int argc, char **argv, char **groups);
void mysql_library_end();

MYSQL_PARAMETERS* mysql_get_parameters();
uint max_allowed_packet(); //{ return *mysql_get_parameters().p_max_allowed_packet; }
uint net_buffer_length(); //{ return *mysql_get_parameters().p_net_buffer_length; }

/*
  Set up and bring down a thread; these function should be called
  for each thread in an application which opens at least one MySQL
  connection.  All uses of the connection(s) should be between these
  function calls.
*/
my_bool mysql_thread_init();
void mysql_thread_end();

/*
  Functions to get information from the MYSQL and MYSQL_RES structures
  Should definitely be used if one uses shared libraries.
*/

my_ulonglong mysql_num_rows(MYSQL_RES* res);
uint mysql_num_fields(MYSQL_RES* res);
my_bool mysql_eof(MYSQL_RES* res);
MYSQL_FIELD* mysql_fetch_field_direct(MYSQL_RES* res, uint fieldnr);
MYSQL_FIELD* mysql_fetch_fields(MYSQL_RES* res);
MYSQL_ROW_OFFSET mysql_row_tell(MYSQL_RES* res);
MYSQL_FIELD_OFFSET mysql_field_tell(MYSQL_RES* res);

uint mysql_field_count(MYSQL* mysql);
my_ulonglong mysql_affected_rows(MYSQL* mysql);
my_ulonglong mysql_insert_id(MYSQL* mysql);
uint mysql_errno(MYSQL* mysql);
const(char*) mysql_error(MYSQL* mysql);
const(char*) mysql_sqlstate(MYSQL* mysql);
uint mysql_warning_count(MYSQL* mysql);
const(char*) mysql_info(MYSQL* mysql);
uint mysql_thread_id(MYSQL* mysql);
const(char*) mysql_character_set_name(MYSQL* mysql);
int mysql_set_character_set(MYSQL* mysql, const char* csname);

MYSQL* mysql_init(MYSQL* mysql);
my_bool mysql_ssl_set(MYSQL* mysql, const char* key,
				      const char* cert, const char* ca,
				      const char* capath, const char* cipher);
const(char*) mysql_get_ssl_cipher(MYSQL* mysql);
my_bool mysql_change_user(MYSQL* mysql, const char* user,
					  const char* passwd, const char* db);
MYSQL* mysql_real_connect(MYSQL* mysql, const char* host,
					   const char* user,
					   const char* passwd,
					   const char* db,
					   uint port,
					   const char* unix_socket,
					   uint clientflag);
int mysql_select_db(MYSQL* mysql, const char* db);
int mysql_query(MYSQL* mysql, const char* q);
int mysql_send_query(MYSQL* mysql, const char* q, uint length);
int mysql_real_query(MYSQL* mysql, const char* q, uint length);
MYSQL_RES* mysql_store_result(MYSQL* mysql);
MYSQL_RES* mysql_use_result(MYSQL* mysql);

void mysql_get_character_set_info(MYSQL* mysql, MY_CHARSET_INFO* charset);

/* local infile support */

immutable uint LOCAL_INFILE_ERROR_LEN = 512;

void
mysql_set_local_infile_handler(MYSQL* mysql,
                               int function(void **, const char *, void *) local_infile_init,
                               int function(void*, char*, uint) local_infile_read,
                               void function(void*) local_infile_end,
                               int function(void*, char*, uint) local_infile_error,
                               void *);

void
mysql_set_local_infile_default(MYSQL* mysql);

int mysql_shutdown(MYSQL* mysql, mysql_enum_shutdown_level shutdown_level);
int mysql_dump_debug_info(MYSQL* mysql);
int mysql_refresh(MYSQL* mysql, uint refresh_options);
int mysql_kill(MYSQL* mysql,uint pid);
int mysql_set_server_option(MYSQL* mysql, enum_mysql_set_option option);
int mysql_ping(MYSQL* mysql);
const(char*)	mysql_stat(MYSQL *mysql);
const(char*) mysql_get_server_info(MYSQL* mysql);
const(char*) mysql_get_client_info();
uint mysql_get_client_version();
const(char*) mysql_get_host_info(MYSQL* mysql);
uint mysql_get_server_version(MYSQL* mysql);
uint mysql_get_proto_info(MYSQL* mysql);
MYSQL_RES*	mysql_list_dbs(MYSQL* mysql, const char* wild);
MYSQL_RES* mysql_list_tables(MYSQL* mysql, const char* wild);
MYSQL_RES* mysql_list_processes(MYSQL* mysql);
int mysql_options(MYSQL* mysql, mysql_option option, const void* arg);
void mysql_free_result(MYSQL_RES* result);
void mysql_data_seek(MYSQL_RES* result, my_ulonglong offset);
MYSQL_ROW_OFFSET mysql_row_seek(MYSQL_RES* result, MYSQL_ROW_OFFSET offset);
MYSQL_FIELD_OFFSET mysql_field_seek(MYSQL_RES* result, MYSQL_FIELD_OFFSET offset);
MYSQL_ROW mysql_fetch_row(MYSQL_RES* result);
uint* mysql_fetch_lengths(MYSQL_RES* result);
MYSQL_FIELD* mysql_fetch_field(MYSQL_RES* result);
MYSQL_RES* mysql_list_fields(MYSQL* mysql, const char* table, const char* wild);
uint mysql_escape_string(char* to,const char* from, uint from_length);
uint mysql_hex_string(char* to,const char* from, uint from_length);
uint mysql_real_escape_string(MYSQL* mysql, char* to,const char* from, uint length);
void mysql_debug(const char* dbg);
void myodbc_remove_escape(MYSQL* mysql,char* name);
uint mysql_thread_safe();
my_bool mysql_embedded();
my_bool mysql_read_query_result(MYSQL* mysql);


/*
  The following definitions are added for the enhanced
  client-server protocol
*/

/* statement state */
enum enum_mysql_stmt_state
{
  MYSQL_STMT_INIT_DONE= 1, MYSQL_STMT_PREPARE_DONE, MYSQL_STMT_EXECUTE_DONE,
  MYSQL_STMT_FETCH_DONE
}


/*
  This structure is used to define bind information, and
  internally by the client library.
  Public members with their descriptions are listed below
  (conventionally `On input' refers to the binds given to
  mysql_stmt_bind_param, `On output' refers to the binds given
  to mysql_stmt_bind_result):

  buffer_type    - One of the MYSQL_* types, used to describe
                   the host language type of buffer.
                   On output: if column type is different from
                   buffer_type, column value is automatically converted
                   to buffer_type before it is stored in the buffer.
  buffer         - On input: points to the buffer with input data.
                   On output: points to the buffer capable to store
                   output data.
                   The type of memory pointed by buffer must correspond
                   to buffer_type. See the correspondence table in
                   the comment to mysql_stmt_bind_param.

  The two above members are mandatory for any kind of bind.

  buffer_length  - the length of the buffer. You don't have to set
                   it for any fixed length buffer: float, double,
                   int, etc. It must be set however for variable-length
                   types, such as BLOBs or STRINGs.

  length         - On input: in case when lengths of input values
                   are different for each execute, you can set this to
                   point at a variable containining value length. This
                   way the value length can be different in each execute.
                   If length is not NULL, buffer_length is not used.
                   Note, length can even point at buffer_length if
                   you keep bind structures around while fetching:
                   this way you can change buffer_length before
                   each execution, everything will work ok.
                   On output: if length is set, mysql_stmt_fetch will
                   write column length into it.

  is_null        - On input: points to a boolean variable that should
                   be set to TRUE for NULL values.
                   This member is useful only if your data may be
                   NULL in some but not all cases.
                   If your data is never NULL, is_null should be set to 0.
                   If your data is always NULL, set buffer_type
                   to MYSQL_TYPE_NULL, and is_null will not be used.

  is_unsigned    - On input: used to signify that values provided for one
                   of numeric types are unsigned.
                   On output describes signedness of the output buffer.
                   If, taking into account is_unsigned flag, column data
                   is out of range of the output buffer, data for this column
                   is regarded truncated. Note that this has no correspondence
                   to the sign of result set column, if you need to find it out
                   use mysql_stmt_result_metadata.
  error          - where to write a truncation error if it is present.
                   possible error value is:
                   0  no truncation
                   1  value is out of range or buffer is too small

  Please note that MYSQL_BIND also has internals members.
*/

struct st_mysql_bind
{
  uint* length;          /* output length pointer */
  my_bool* is_null;	  /* Pointer to null indicator */
  void* buffer;	  /* buffer to get/put data */
  /* set this if you want to track data truncations happened during fetch */
  my_bool* error;
  ubyte* row_ptr;         /* for the current data position */
  void function(NET *net, st_mysql_bind* param) store_param_func;
  void function(st_mysql_bind*, MYSQL_FIELD*, ubyte** row) fetch_result;
  void function(st_mysql_bind*, MYSQL_FIELD*, ubyte** row) skip_result;
  /* output buffer length, must be set when fetching str/binary */
  uint buffer_length;
  uint offset;           /* offset position for char/binary fetch */
  uint length_value;     /* Used if length is 0 */
  uint param_number;	  /* For null count and error messages */
  uint pack_length;	  /* Internal length for packed data */
  enum_field_types buffer_type;	/* buffer type */
  my_bool       error_value;      /* used if error is 0 */
  my_bool       is_unsigned;      /* set if integer type is unsigned */
  my_bool	long_data_used;	  /* If used with mysql_send_long_data */
  my_bool	is_null_value;    /* Used if is_null is 0 */
  void* extension;
}
alias st_mysql_bind MYSQL_BIND;


struct st_mysql_stmt_extension;

/* statement handler */
struct st_mysql_stmt
{
  MEM_ROOT       mem_root;             /* root allocations */
  LIST           list;                 /* list to keep track of all stmts */
  MYSQL*         mysql;               /* connection handle */
  MYSQL_BIND*    params;              /* input parameters */
  MYSQL_BIND*    bind;                /* output parameters */
  MYSQL_FIELD*   fields;              /* result set metadata */
  MYSQL_DATA     result;               /* cached result set */
  MYSQL_ROWS*    data_cursor;         /* current row in cached result */
  /*
    mysql_stmt_fetch() calls this function to fetch one row (it's different
    for buffered, unbuffered and cursor fetch).
  */
  int function(st_mysql_stmt* stmt, ubyte** row) read_row_func;
  /* copy of mysql->affected_rows after statement execution */
  my_ulonglong   affected_rows;
  my_ulonglong   insert_id;            /* copy of mysql->insert_id */
  uint stmt_id;	       /* Id for prepared statement */
  uint  flags;                /* i.e. type of cursor to open */
  uint  prefetch_rows;        /* number of rows per one COM_FETCH */
  /*
    Copied from mysql->server_status after execute/fetch to know
    server-side cursor status for this statement.
  */
  uint   server_status;
  uint	 last_errno;	       /* error code */
  uint   param_count;          /* input parameter count */
  uint   field_count;          /* number of columns in result set */
  enum_mysql_stmt_state state;    /* statement state */
  char[MYSQL_ERRMSG_SIZE] last_error; /* error message */
  char[SQLSTATE_LENGTH+1] sqlstate;
  /* Types of input parameters should be sent to server */
  my_bool        send_types_to_server;
  my_bool        bind_param_done;      /* input buffers were supplied */
  ubyte  bind_result_done;     /* output buffers were supplied */
  /* mysql_stmt_close() had to cancel this result */
  my_bool       unbuffered_fetch_cancelled;
  /*
    Is set to true if we need to calculate field->max_length for
    metadata fields when doing mysql_stmt_store_result.
  */
  my_bool       update_max_length;
  st_mysql_stmt_extension *extension;
}
alias st_mysql_stmt MYSQL_STMT;

enum enum_stmt_attr_type
{
  /*
    When doing mysql_stmt_store_result calculate max_length attribute
    of statement metadata. This is to be consistent with the old API,
    where this was done automatically.
    In the new API we do that only by request because it slows down
    mysql_stmt_store_result sufficiently.
  */
  STMT_ATTR_UPDATE_MAX_LENGTH,
  /*
    unsigned long with combination of cursor flags (read only, for update,
    etc)
  */
  STMT_ATTR_CURSOR_TYPE,
  /*
    Amount of rows to retrieve from server per one fetch if using cursors.
    Accepts unsigned long attribute in the range 1 - ulong_max
  */
  STMT_ATTR_PREFETCH_ROWS
};


MYSQL_STMT* mysql_stmt_init(MYSQL* mysql);
int mysql_stmt_prepare(MYSQL_STMT* stmt, const char* query, uint length);
int mysql_stmt_execute(MYSQL_STMT* stmt);
int mysql_stmt_fetch(MYSQL_STMT* stmt);
int mysql_stmt_fetch_column(MYSQL_STMT* stmt, MYSQL_BIND* bind_arg,
                                    uint column,
                                    uint offset);
int mysql_stmt_store_result(MYSQL_STMT* stmt);
uint mysql_stmt_param_count(MYSQL_STMT* stmt);
my_bool mysql_stmt_attr_set(MYSQL_STMT* stmt,
                                    enum_stmt_attr_type attr_type,
                                    const void* attr);
my_bool mysql_stmt_attr_get(MYSQL_STMT* stmt,
                                    enum_stmt_attr_type attr_type,
                                    void* attr);
my_bool mysql_stmt_bind_param(MYSQL_STMT* stmt, MYSQL_BIND* bnd);
my_bool mysql_stmt_bind_result(MYSQL_STMT* stmt, MYSQL_BIND* bnd);
my_bool mysql_stmt_close(MYSQL_STMT* stmt);
my_bool mysql_stmt_reset(MYSQL_STMT* stmt);
my_bool mysql_stmt_free_result(MYSQL_STMT*stmt);
my_bool mysql_stmt_send_long_data(MYSQL_STMT* stmt,
                                          uint param_number,
                                          const char* data,
                                          uint length);
MYSQL_RES* mysql_stmt_result_metadata(MYSQL_STMT* stmt);
MYSQL_RES* mysql_stmt_param_metadata(MYSQL_STMT* stmt);
uint mysql_stmt_errno(MYSQL_STMT* stmt);
const(char*) mysql_stmt_error(MYSQL_STMT* stmt);
const(char*) mysql_stmt_sqlstate(MYSQL_STMT* stmt);
MYSQL_ROW_OFFSET mysql_stmt_row_seek(MYSQL_STMT* stmt, MYSQL_ROW_OFFSET offset);
MYSQL_ROW_OFFSET mysql_stmt_row_tell(MYSQL_STMT* stmt);
void mysql_stmt_data_seek(MYSQL_STMT* stmt, my_ulonglong offset);
my_ulonglong mysql_stmt_num_rows(MYSQL_STMT* stmt);
my_ulonglong mysql_stmt_affected_rows(MYSQL_STMT* stmt);
my_ulonglong mysql_stmt_insert_id(MYSQL_STMT* stmt);
uint mysql_stmt_field_count(MYSQL_STMT* stmt);

my_bool mysql_commit(MYSQL* mysql);
my_bool mysql_rollback(MYSQL* mysql);
my_bool mysql_autocommit(MYSQL* mysql, my_bool auto_mode);
my_bool mysql_more_results(MYSQL* mysql);
int mysql_next_result(MYSQL* mysql);
int mysql_stmt_next_result(MYSQL_STMT* stmt);
void mysql_close(MYSQL* sock);


/* status return codes */
immutable int MYSQL_NO_DATA = 100;
immutable int MYSQL_DATA_TRUNCATED = 101;

void mysql_reload(MYSQL* mysql) { mysql_refresh(mysql, REFRESH_GRANT); }
/*
#ifdef USE_OLD_FUNCTIONS
MYSQL *		STDCALL mysql_connect(MYSQL *mysql, const char *host,
				      const char *user, const char *passwd);
int		STDCALL mysql_create_db(MYSQL *mysql, const char *DB);
int		STDCALL mysql_drop_db(MYSQL *mysql, const char *DB);
#endif
*/
immutable bool HAVE_MYSQL_REAL_CONNECT = true;

