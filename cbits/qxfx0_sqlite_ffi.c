#include <sqlite3.h>

int qxfx0_sqlite3_bind_text_transient(sqlite3_stmt *stmt, int idx, const char *text, int nbytes) {
    return sqlite3_bind_text(stmt, idx, text, nbytes, SQLITE_TRANSIENT);
}
