
$(document).ready( function () {
  $('.mac').mouseenter( function () {
    $('.mac[data-mac='+$(this).attr('data-mac')+']').addClass('macOver');
  });
  $('.mac').mouseleave( function () {
    $('.mac[data-mac='+$(this).attr('data-mac')+']').removeClass('macOver');
  });
  $('#arpTable .mac').each( function () {
	  if($(this).attr('title')) {
		  $(this).addClass('macNoted');
	  }
  });
});

