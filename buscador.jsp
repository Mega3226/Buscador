// Updated SQL logic for combined text and application searches
String query = "SELECT * FROM applications WHERE (name LIKE ? OR description LIKE ?) AND (status = ?)";
PreparedStatement preparedStatement = connection.prepareStatement(query);
preparedStatement.setString(1, "%" + searchText + "%");
preparedStatement.setString(2, "%" + searchText + "%");
preparedStatement.setString(3, applicationStatus);
ResultSet resultSet = preparedStatement.executeQuery(); 
// Process results
