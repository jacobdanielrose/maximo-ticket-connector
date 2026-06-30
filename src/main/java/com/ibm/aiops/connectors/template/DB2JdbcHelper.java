package com.ibm.aiops.connectors.template;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Properties;
import java.util.logging.Level;
import java.util.logging.Logger;

import com.ibm.aiops.connectors.template.model.Configuration;

/**
 * Helper class for managing DB2 JDBC connections to Maximo database
 */
public class DB2JdbcHelper {

    static final Logger logger = Logger.getLogger(DB2JdbcHelper.class.getName());

    private Configuration config;
    private String jdbcUrl;
    private Properties connectionProps;

    public DB2JdbcHelper(Configuration config) {
        this.config = config;
        initializeConnectionProperties();
    }

    /**
     * Initialize JDBC connection properties from configuration
     */
    private void initializeConnectionProperties() {
        // Build JDBC URL — prefer explicit jdbcUrl, then fall back to url (populated by
        // the UI form), then construct from individual host/port/dbName fields.
        if (config.getJdbcUrl() != null && !config.getJdbcUrl().isEmpty()) {
            this.jdbcUrl = config.getJdbcUrl();
        } else if (config.getUrl() != null && config.getUrl().startsWith("jdbc:")) {
            this.jdbcUrl = config.getUrl();
        } else {
            String host = config.getDbHost() != null ? config.getDbHost() : "localhost";
            String port = config.getDbPort() != null ? config.getDbPort() : "50001";
            String dbName = config.getDbName() != null ? config.getDbName() : "MAXDB76";
            this.jdbcUrl = String.format("jdbc:db2://%s:%s/%s:sslConnection=true;", host, port, dbName);
        }

        // Setup connection properties
        connectionProps = new Properties();
        connectionProps.setProperty("user", config.getUsername());
        connectionProps.setProperty("password", config.getPassword());

        if (config.getDbSchema() != null && !config.getDbSchema().isEmpty()) {
            connectionProps.setProperty("currentSchema", config.getDbSchema());
        }

        connectionProps.setProperty("retrieveMessagesFromServerOnGetMessage", "true");
        connectionProps.setProperty("progressiveStreaming", "2");

        logger.log(Level.INFO, "JDBC URL configured: " + jdbcUrl);
    }

    /**
     * Get a database connection
     */
    public Connection getConnection() throws SQLException {
        try {
            Class.forName("com.ibm.db2.jcc.DB2Driver");
            Connection conn = DriverManager.getConnection(jdbcUrl, connectionProps);
            logger.log(Level.INFO, "Successfully connected to DB2 database");
            return conn;
        } catch (ClassNotFoundException e) {
            logger.log(Level.SEVERE, "DB2 JDBC Driver not found", e);
            throw new SQLException("DB2 JDBC Driver not found: " + e.getMessage());
        } catch (SQLException e) {
            logger.log(Level.SEVERE, "Failed to connect to database: " + jdbcUrl, e);
            throw e;
        }
    }

    /**
     * Test the database connection
     */
    public boolean testConnection() {
        Connection conn = null;
        try {
            conn = getConnection();
            return conn != null && !conn.isClosed();
        } catch (SQLException e) {
            logger.log(Level.WARNING, "Connection test failed", e);
            return false;
        } finally {
            closeConnection(conn);
        }
    }

    public ResultSet executeQuery(String query) throws SQLException {
        Connection conn = getConnection();
        PreparedStatement stmt = conn.prepareStatement(query);
        return stmt.executeQuery();
    }

    public ResultSet executeQuery(String query, Object... params) throws SQLException {
        Connection conn = getConnection();
        PreparedStatement stmt = conn.prepareStatement(query);
        for (int i = 0; i < params.length; i++) {
            stmt.setObject(i + 1, params[i]);
        }
        return stmt.executeQuery();
    }

    public void closeConnection(Connection conn) {
        if (conn != null) {
            try {
                conn.close();
            } catch (SQLException e) {
                logger.log(Level.WARNING, "Error closing connection", e);
            }
        }
    }

    public void closeResultSet(ResultSet rs) {
        if (rs != null) {
            try {
                rs.close();
            } catch (SQLException e) {
                logger.log(Level.WARNING, "Error closing ResultSet", e);
            }
        }
    }

    public void closeStatement(PreparedStatement stmt) {
        if (stmt != null) {
            try {
                stmt.close();
            } catch (SQLException e) {
                logger.log(Level.WARNING, "Error closing PreparedStatement", e);
            }
        }
    }

    public void closeResources(Connection conn, PreparedStatement stmt, ResultSet rs) {
        closeResultSet(rs);
        closeStatement(stmt);
        closeConnection(conn);
    }

    public String getJdbcUrl() {
        return jdbcUrl;
    }
}

// Made with Bob
