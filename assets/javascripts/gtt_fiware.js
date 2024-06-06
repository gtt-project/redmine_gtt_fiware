function showNotification(message) {
  // Get the notification box
  var notification = document.getElementById('temporaryNotification');

  // Change the text of the notification box
  notification.textContent = message;

  // Show the notification box
  notification.classList.add('visible');

  // Hide the notification box after 3 seconds
  setTimeout(function() {
    notification.classList.remove('visible');
  }, 3000);
}
