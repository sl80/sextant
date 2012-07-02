	def icon_show; "<form action='#{scaffold_url("show#{@scaffold_suffix}", :id=>@scaffold_object.scaffold_id)}' method='get' >
		<input type='image' src='/images/file.png' alt='Anzeigen'></form>"; end
	def icon_edit; "<form action='#{scaffold_url("edit#{@scaffold_suffix}", :id=>@scaffold_object.scaffold_id)}' method='get' >
		<input type='image' src='/images/file_edit.png' alt='Bearbeiten'></form>"; end
	def icon_destroy; "<form action='#{scaffold_url("destroy#{@scaffold_suffix}", :id=>@scaffold_object.scaffold_id)}' method='post' >
		<input type='image' src='/images/trash.png' alt='Löschen'></form>"; end
	def icon_new; "<form action='/app/new#{@scaffold_suffix}' method='get' >
		<input type='image' src='/images/file_add.png' alt='Neu'></form>"; end
	def icon_search; "<form action='/app/search#{@scaffold_suffix}' method='get' >
		<input type='image' src='/images/magnify.png' alt='Suchen'></form>" ; end
	def icon_browse; "<form action='/app/browse#{@scaffold_suffix}' method='get' >
		<input type='image' src='/images/book.png' alt='Liste'></form>"; end
