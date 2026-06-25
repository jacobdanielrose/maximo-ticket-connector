package com.ibm.aiops.connectors.template;

import java.security.KeyManagementException;
import java.security.NoSuchAlgorithmException;
import java.security.cert.X509Certificate;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Properties;
import java.util.logging.Level;
import java.util.logging.Logger;

import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

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
            // Construct JDBC URL from components
            String host = config.getDbHost() != null ? config.getDbHost() : "localhost";
            String port = config.getDbPort() != null ? config.getDbPort() : "50000";
            String dbName = config.getDbName() != null ? config.getDbName() : "MAXDB76";

            this.jdbcUrl = String.format("jdbc:db2://%s:%s/%s", host, port, dbName);

            // Add SSL if configured
            if (config.isUseSSL()) {
                this.jdbcUrl += ":sslConnection=true;";
            }
        }

        // Setup connection properties
        connectionProps = new Properties();
        connectionProps.setProperty("user", config.getUsername());
        connectionProps.setProperty("password", config.getPassword());

        // Set current schema if provided
        if (config.getDbSchema() != null && !config.getDbSchema().isEmpty()) {
            connectionProps.setProperty("currentSchema", config.getDbSchema());
        }

        // Additional DB2 specific properties
        connectionProps.setProperty("retrieveMessagesFromServerOnGetMessage", "true");
        connectionProps.setProperty("progressiveStreaming", "2");

        // Skip SSL cert validation by installing a trust-all SSLContext.
        // Triggered explicitly by the skipCertValidation toggle, or automatically
        // when sslConnection=true is present but no truststore is configured —
        // which is the common case for MAS DB2 with a self-signed certificate.
        boolean autoSkip = this.jdbcUrl.contains("sslConnection=true")
                && (config.getSslTrustStore() == null || config.getSslTrustStore().isEmpty());
        if (config.isSkipCertValidation() || autoSkip) {
            this.jdbcUrl = this.jdbcUrl.replaceAll(";?sslCertLocation=[^;]*", "")
                    .replaceAll(";?sslTrustStoreLocation=[^;]*", "");
            installTrustAllSslContext();
            logger.log(Level.WARNING, "SSL certificate validation is disabled (self-signed cert mode)");
        }

        logger.log(Level.INFO, "JDBC URL configured: " + jdbcUrl);
    }

    /**
     * Install a trust-all SSLContext so the IBM DB2 JDBC driver accepts any certificate.
     */
    private void installTrustAllSslContext() {
        try {
            TrustManager[] trustAll = new TrustManager[] {
                new X509TrustManager() {
                    public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
                    public void checkClientTrusted(X509Certificate[] c, String a) {}
                    public void checkServerTrusted(X509Certificate[] c, String a) {}
                }
            };
            SSLContext sc = SSLContext.getInstance("TLS");
            sc.init(null, trustAll, new java.security.SecureRandom());
            SSLContext.setDefault(sc);
        } catch (NoSuchAlgorithmException | KeyManagementException e) {
            logger.log(Level.WARNING, "Failed to install trust-all SSLContext", e);
        }
    }

    /**
     * Get a database connection
     *
     * @return Connection object
     *
     * @throws SQLException
     *             if connection fails
     */
    public Connection getConnection() throws SQLException {
        try {
            // Load DB2 JDBC driver
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
     *
     * @return true if connection is successful, false otherwise
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

    /**
     * Execute a query and return ResultSet
     *
     * @param query
     *            SQL query to execute
     *
     * @return ResultSet containing query results
     *
     * @throws SQLException
     *             if query execution fails
     */
    public ResultSet executeQuery(String query) throws SQLException {
        Connection conn = getConnection();
        PreparedStatement stmt = conn.prepareStatement(query);
        return stmt.executeQuery();
    }

    /**
     * Execute a parameterized query
     *
     * @param query
     *            SQL query with parameters
     * @param params
     *            Parameters to bind to the query
     *
     * @return ResultSet containing query results
     *
     * @throws SQLException
     *             if query execution fails
     */
    public ResultSet executeQuery(String query, Object... params) throws SQLException {
        Connection conn = getConnection();
        PreparedStatement stmt = conn.prepareStatement(query);

        // Bind parameters
        for (int i = 0; i < params.length; i++) {
            stmt.setObject(i + 1, params[i]);
        }

        return stmt.executeQuery();
    }

    /**
     * Close database connection safely
     *
     * @param conn
     *            Connection to close
     */
    public void closeConnection(Connection conn) {
        if (conn != null) {
            try {
                conn.close();
                logger.log(Level.FINE, "Database connection closed");
            } catch (SQLException e) {
                logger.log(Level.WARNING, "Error closing connection", e);
            }
        }
    }

    /**
     * Close ResultSet safely
     *
     * @param rs
     *            ResultSet to close
     */
    public void closeResultSet(ResultSet rs) {
        if (rs != null) {
            try {
                rs.close();
            } catch (SQLException e) {
                logger.log(Level.WARNING, "Error closing ResultSet", e);
            }
        }
    }

    /**
     * Close PreparedStatement safely
     *
     * @param stmt
     *            PreparedStatement to close
     */
    public void closeStatement(PreparedStatement stmt) {
        if (stmt != null) {
            try {
                stmt.close();
            } catch (SQLException e) {
                logger.log(Level.WARNING, "Error closing PreparedStatement", e);
            }
        }
    }

    /**
     * Close all resources safely
     *
     * @param conn
     *            Connection to close
     * @param stmt
     *            PreparedStatement to close
     * @param rs
     *            ResultSet to close
     */
    public void closeResources(Connection conn, PreparedStatement stmt, ResultSet rs) {
        closeResultSet(rs);
        closeStatement(stmt);
        closeConnection(conn);
    }

    /**
     * Get the configured JDBC URL
     *
     * @return JDBC URL string
     */
    public String getJdbcUrl() {
        return jdbcUrl;
    }
}

// Made with Bob
