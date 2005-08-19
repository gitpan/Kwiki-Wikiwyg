package Kwiki::Wikiwyg;
use Kwiki::Plugin -Base;
use mixin 'Kwiki::Installer';
our $VERSION = '0.10'; 

my $ndash = chr(8211);
field 'output';

const class_id => 'wikiwyg';
const css_file => 'wikiwyg.css';
const config_file => 'wikiwyg.yaml';
const cgi_class => 'Kwiki::Wikiwyg::CGI';

sub register {
    my $registry = shift;
    $registry->add(action => 'wikiwyg_save_html');
    $registry->add(action => 'wikiwyg_save_wikitext');
    $registry->add(action => 'wikiwyg_html_to_html');
    $registry->add(action => 'wikiwyg_html_to_wikitext');
    $registry->add(action => 'wikiwyg_wikitext_to_html');
    $registry->add(preference => $self->wikiwyg_use);
    $registry->add(hook => 'display:display', pre => 'add_library');
    #$registry->add(prerequisite => 'ajax');
}

sub wikiwyg_use {
    my $p = $self->new_preference('wikiwyg_use');
    $p->query('Use the experimental Firefox Wysiwyg Editor');
    $p->type('boolean');
    $p->default(0);
    return $p;
}

sub add_library {
    return unless $self->preferences->wikiwyg_use->value;
    $self->hub->css->add_file('wikiwyg.css');
    $self->hub->javascript->add_file('wikiwyg.js');
    $self->hub->javascript->add_file('wikiwyg_kwiki.js');
}

sub wikiwyg_wikitext_to_html {
    my $wikitext = $self->cgi->content;
    return $self->hub->formatter->text_to_html($wikitext);
}

sub wikiwyg_html_to_wikitext {
    my $html = $self->cgi->content;
    return $self->html_to_wikitext($html);
}

sub wikiwyg_html_to_html {
    my $html = $self->cgi->content;
    my $content = $self->html_to_wikitext($html);
    $self->hub->formatter->text_to_html($content);
}

sub wikiwyg_save_wikitext {
    my $wikitext = $self->cgi->content;
    return $self->save($wikitext);
}

sub wikiwyg_save_html {
    my $html = $self->cgi->content;
    my $wikitext = $self->html_to_wikitext($html);
    return $self->save($wikitext);
}

sub html_to_wikitext {
    require HTML::TreeBuilder;
    my $html = shift;
    my $tree = HTML::TreeBuilder->new_from_content($html)
      or return;
    my $output = '';
    $self->output(\$output);
    $self->walk($tree);
    $self->single_newline;
    return $output;
}

sub walk {
    my $element = shift;
    return unless defined $element;
    for my $part ($element->content_list) {
        if (ref $part) {
            my $tag = $part->tag or die;
            my $method = "format_" . lc($tag);
            XXX("We don't yet support the '$tag' tag.  Forgiveness, please.\n",
                 $part)
              unless $self->can($method);
            $self->$method($part);
        }
        elsif ($part && $part =~ /\S/) {
            $part =~ s/$ndash/--/g;
            $self->append($part);
        }
    }
}

sub append {
    my $output = $self->output;
    $$output .= shift;
}

sub single_newline {
    my $output = $self->output;
    $$output =~ s/\n+\z//;
    $self->append("\n") if length $$output;
}

sub double_newline {
    my $output = $self->output;
    $$output =~ s/\n+\z//;
    $self->append("\n\n") if length $$output;
}

sub format_head {}
sub format_body {
    $self->walk(@_);
}

sub format_span {
    my ($span) = @_;
    my $style = $span->attr('style') || '';
    return $self->format_em(@_)
      if $style =~ /italic;/;
    return $self->format_strong(@_)
      if $style =~ /bold;/;
    return $self->format_u(@_)
      if $style =~ /underline;/;
    return $self->format_del(@_)
      if $style =~ /line-through;/;
    XXX($style);
}

sub format_table {
    $self->double_newline;
    $self->walk(@_);
    $self->double_newline;
}

sub format_tbody {
    $self->walk(@_);
}

my $first_cell;
sub format_tr {
    $first_cell = 1;
    $self->walk(@_);
    $self->append(" |\n");
}

sub format_td {
    $self->append(' ') unless $first_cell;
    $self->append('| ');
    $self->walk(@_);
    $first_cell = 0;
}

sub format_pre {
    my $pre = shift;
    XXX($pre->content);
}

sub format_br {}

sub format_nobr {
    $self->walk(map { s/\n/ /g; $_ } @_);
}

sub format_font { $self->walk(@_) }

sub format_blockquote { $self->walk(@_) }

sub format_hr {
    $self->double_newline;
    $self->append('----');
    $self->double_newline;
}

sub header {
    $self->append(('=' x shift) . ' ');
    $self->walk(@_);
    $self->double_newline;
}

sub format_h1 { $self->header(1, @_) }
sub format_h2 { $self->header(2, @_) }
sub format_h3 { $self->header(3, @_) }
sub format_h4 { $self->header(4, @_) }
sub format_h5 { $self->header(5, @_) }
sub format_h6 { $self->header(6, @_) }

sub format_p {
    my ($p) = @_;
    $self->double_newline;
    shift @{$p->{_content}}
      if ref($p->{_content}[0]) and $p->{_content}[0]{_tag} eq 'br';
    $p->{_content}[0] =~ s/^\s+//;
    $self->walk(@_);
    $self->double_newline;
}

sub wrap_char {
    my $char = shift;
    $self->append($char);
    $self->walk(@_);
    $self->append($char);
}

sub format_strong { $self->wrap_char('*', @_) }
sub format_b { $self->format_strong(@_) }
sub format_em { $self->wrap_char('/', @_) }
sub format_i { $self->format_em(@_) }
sub format_u { $self->wrap_char('_', @_); }
sub format_del { $self->wrap_char('-', @_); }

my $bullet = '';

sub list {
    my $marker = shift;
    $bullet = $marker x (length($bullet) + 1);
    $self->walk(@_);
    $bullet =~ s/.//;
    return $self->double_newline
      unless length $bullet;
    $self->single_newline;
}

sub format_ul {
    $self->list('*', @_);
}

sub format_ol {
    $self->list('0', @_);
}

sub format_li {
    $self->append("$bullet ");
    $self->walk(@_);
    $self->single_newline;
}

sub format_img {
    my ($img) = @_;
    my $href = $img->attr('src') or return;
    $self->append($href);
}

sub format_a {
    my ($a) = @_;
    my $text = shift @{$a->content};
    my $href = $a->attr('href');
    my $formatted = $text =~ /^\w+$/
    ? $text =~ /[A-Z]/
      ? $text
      : "[$text]"
    : $text eq $href
      ? $href
      : "[$text $href]";
    $self->append($formatted);
}

# XXX Duplication from Kwiki::Display
sub display {
    my $page = $self->pages->current;
    return $self->redirect('')
      unless $page;
    my $page_title = $page->title;
    my $page_uri = $page->uri;
    return $self->redirect("action=edit;page_name=$page_uri")
      if not($page->exists) and $self->have_plugin('edit');
    my $script = $self->config->script_name;
    my $screen_title = $self->hub->have_plugin('search')
    ? "<a href=\"$script?action=search;search_term=$page_uri\">$page_title</a>"
    : $page_title;
    eval {
        $page->content;
    };
    if ($@) {
        my $main_page = $self->config->main_page;
        die $@ if $page->title eq $main_page;
        return $self->redirect($main_page);
    }
    $self->render_screen(
        screen_title => $screen_title,
        page_html => $page->to_html,
        page_content => $page->content,
    );
}

# XXX Duplication from Kwiki::Edit
sub save {
    my $content = shift;
    return $self->redirect($self->pages->current->uri)
      unless defined $content;
    my $page = $self->pages->current;
    $page->content($content);
#     if ($page->modified_time != $self->cgi->page_time) {
#         my $page_uri = $page->uri;
#         return $self->redirect("action=edit_contention;page_name=$page_uri");
#     }
    $page->update->store;
    return $self->redirect($page->uri);
}

package Kwiki::Wikiwyg::CGI;
use base 'Kwiki::CGI';

cgi 'html' => qw(-utf8 -newlines);
cgi 'content' => qw(-utf8 -newlines);
cgi 'page_time';

package Kwiki::Wikiwyg;

__DATA__

=head1 NAME

Kwiki::Wikiwyg - Wysiwyg Editing for Kwiki

=head1 SYNOPSIS

    http://openjsan.org/doc/i/in/ingy/Wikiwyg/0.10/lib/Wikiwyg.html

=head1 DESCRIPTION

=head1 AUTHOR

Brian Ingerson <ingy@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2005. Brian Ingerson. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut

__config/wikiwyg.yaml__
# DO NOT EDIT THIS FILE
# Put overrides in the top level config.yaml
# See: http://www.kwiki.org/?ChangingConfigDotYaml
#
# DO NOT EDIT THIS FILE
# Put overrides in the top level config.yaml
# See: http://www.kwiki.org/?ChangingConfigDotYaml
#
# DO NOT EDIT THIS FILE
# Put overrides in the top level config.yaml
# See: http://www.kwiki.org/?ChangingConfigDotYaml
#
wikiwyg_default: 0
__javascript/wikiwyg_kwiki.js__
window.onload = function() {
    config = {
        baseUri: '',
        doubleClickToEdit: true,
    };
    var elements = document.getElementsByTagName('div');
    var mydiv;
    for (var i = 0; i < elements.length; i++)
        if (elements[i].getAttribute('class') == 'wiki') {
            mydiv = elements[i];
            break;
        }
    wikiwyg = new Wikiwyg.Kwiki();
    wikiwyg.createWikiwygArea(mydiv, config);
    if (!wikiwyg.enabled) 
        return true;
    var elems = document.getElementsByTagName('a');
    for (var i = 0; i < elems.length; i++) {
        var elem = elems[i];
        var match = elem.href.match(/action=edit;page_name=(\w+)/);
        if (match) {
            wikiwyg.page_name = match[1];
            elem.onclick = function() {
                wikiwyg.editMode();
                return false;
            };
            elem.href = "#";
        }
    }
    return true;
}


Wikiwyg.Kwiki = function() {};
Wikiwyg.Kwiki.prototype = new Wikiwyg();

Wikiwyg.Kwiki.prototype.submit_action_form = function(action, value) {
    value['action'] = action;
    var form = document.createElement('form');
    form.setAttribute('action', 'index.cgi');
    form.setAttribute('method', 'POST');
    for (var name in value) {
        var input = document.createElement('input');
        input.setAttribute('type', 'hidden');
        input.setAttribute('name', name);
        input.setAttribute('value', value[name])
        form.appendChild(input);
    }
    var div = this.div;
    div.parentNode.insertBefore(form, div);
    form.submit();
}

Wikiwyg.Kwiki.prototype.saveChanges = function() {
    var self = this;
    var send_wikitext = function(wikitext) {
        self.submit_action_form(
            'wikiwyg_save_wikitext',
            { 'page_name': self.page_name, 'content': wikitext }
        );
    }
    if (this.current_mode.className == 'Wikiwyg.Wikitext.Kwiki') {
        var wikitext = self.current_mode.textarea.value;
        send_wikitext(wikitext);
    } else {
        var html = this.current_mode.rawHtml();
        self.call_action(
            'wikiwyg_html_to_wikitext',
            html,
            send_wikitext
        );
    }
    this.displayMode();
}

Wikiwyg.Kwiki.prototype.modeList = [
    'Wikiwyg.Wysiwyg',
    'Wikiwyg.Wikitext.Kwiki',
    'Wikiwyg.Preview.Kwiki'
];
    
Wikiwyg.Kwiki.prototype.call_action = function(action, content, func) {
    var postdata = 'action=' + action + 
                   ';page_name=' + this.page_name + 
                   ';content=' + encodeURIComponent(content);
    Wikiwyg.live_update(
        'index.cgi',
        postdata,
        func
    );
}

Wikiwyg.Wikitext.Kwiki = function() {};
Wikiwyg.Wikitext.Kwiki.prototype = new Wikiwyg.Wikitext();
Wikiwyg.Wikitext.Kwiki.prototype.className =
  'Wikiwyg.Wikitext.Kwiki';

Wikiwyg.Wikitext.Kwiki.prototype.convertWikitextToHtml =
function(wikitext, func) {
    this.wikiwyg.call_action(
        'wikiwyg_wikitext_to_html', 
        wikitext,
        func
    );
}

Wikiwyg.Wikitext.Kwiki.prototype.convertHtmlToWikitext =
function(html, func) {
    this.wikiwyg.call_action(
        'wikiwyg_html_to_wikitext',
        html,
        func
    );
}


Wikiwyg.Preview.Kwiki = function() {};
Wikiwyg.Preview.Kwiki.prototype = new Wikiwyg.Preview();
Wikiwyg.Preview.Kwiki.prototype.className =
  'Wikiwyg.Preview.Kwiki';

Wikiwyg.Preview.Kwiki.prototype.fromHtml = function(html) {
    var self = this;
    this.wikiwyg.call_action(
        'wikiwyg_html_to_html',
        html,
        function(value) { self.div.innerHTML = value }
    );
}

__javascript/wikiwyg.js__
/*==============================================================================
Wikiwyg - Turn any HTML div into a wikitext /and/ wysiwyg edit area.

DESCRIPTION:

Wikiwyg is a Javascript library that can be easily integrated into any
wiki or blog software. It offers the user multiple ways to edit/view a
piece of content: Wysiwyg, Wikitext, Raw-HTML and Preview.

The library is easy to use, completely object oriented, configurable and
extendable.

See the Wikiwyg documentation for details.

AUTHORS:

    Brian Ingerson <ingy@cpan.org>
    Chris Dent <cdent@burningchrome.com>
    Dave Rolsky <autarch@urth.org>
    Matt Liggett <mml@pobox.com>

COPYRIGHT:

    Copyright (c) 2005 Socialtext Corporation 
    655 High Street
    Palo Alto, CA 94301 U.S.A.
    All rights reserved.

Wikiwyg is free software. 

This library is free software; you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation; either version 2.1 of the License, or (at
your option) any later version.

This library is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
General Public License for more details.

    http://www.gnu.org/copyleft/lesser.txt

 =============================================================================*/

/*==============================================================================
Developer's Notes:

TODO:
    * Release code to JSAN
    * Integrate back into a working Kwiki
    ** With a Wikiwyg.Kwiki subclass
    * Support IE
    * Merge config (default, class attributes, custom)
    * Finish toolbar
    ** Insert Link
    ** Insert Table
    ** Insert Image
    * add Rawhtml mode
    * Make toolbar button width configurable (for small text areas)
    * Make sure we display 'Loading...' whenever we switch modes and have to
      wait.

REFACTOR:
    * Find a good way to call super methods

BUGS:
    * Control-key shortcuts don't work after preview (sometimes)

IDEAS:
    * Spike an integration with TiddlyWiki
    * Make a greasemonkey overlay for Flickr comments 
    * Spike integration with these wikis:
    ** Media Wiki
    ** TWiki
    ** MoinMoin
 =============================================================================*/

/*==============================================================================
Wikiwyg - Primary Wikiwyg base class
 =============================================================================*/

// Constructor and class methods
Wikiwyg = function() {};
Wikiwyg.VERSION = '0.10';

Wikiwyg.is_gecko = (navigator.userAgent.toLowerCase().indexOf("gecko") != -1);
Wikiwyg.browserIsSupported = Wikiwyg.is_gecko;

// Config attributes
// Override these values in a subclass to control which modes
Wikiwyg.prototype.toolbarClass = 'Wikiwyg.Toolbar';
Wikiwyg.prototype.modeList = [ 
    'Wikiwyg.Wysiwyg',
    'Wikiwyg.Wikitext',
    'Wikiwyg.Preview'
];

// Wikiwyg environment setup public methods
Wikiwyg.prototype.createWikiwygArea = function(div, config) {
    this.set_config(config);
    this.initializeObject(div);
};

Wikiwyg.prototype.defaultConfig = function() {
    return {
        baseUri: '',
        doubleClickToEdit: false,
    };
}

Wikiwyg.prototype.initializeObject = function(div) {
    if (! Wikiwyg.browserIsSupported) return;
    if (this.enabled) return;
    this.enabled = true;
    this.div = div;
    this.divHeight = this.div.clientHeight;

    this.mode_objects = {};
    for (var i in this.modeList) {
        var class_name = this.modeList[i];
        var mode_object = eval('new ' + class_name + '()');
        mode_object.initializeObject(this);
        this.mode_objects[class_name] = mode_object;
        if (! this.first_mode) {
            this.first_mode = mode_object;
        }
    }

    if (this.toolbarClass) {
        this.toolbarObject = eval('new ' + this.toolbarClass + '()');
        this.toolbarObject.initializeObject(this);
        this.insert_div_before(this.toolbarObject.div);
    }

    // These objects must be _created_ before the toolbar is created
    // but _inserted_ after.
    for (var key in this.mode_objects) {
        var mode_object = this.mode_objects[key];
        this.insert_div_before(mode_object.div);
    }

    if (this.config.doubleClickToEdit) {
        var self = this;
        this.div.ondblclick = function() { self.editMode() }; 
    }
}

// Wikiwyg environment setup private methods
Wikiwyg.prototype.set_config = function(user_config) {
    this.config = this.defaultConfig();
    if (user_config == null) return;
    for (var key in this.config) {
        if (user_config[key] != null)
            this.config[key] = user_config[key];
    }
}

Wikiwyg.prototype.insert_div_before = function(div) {
    div.style.display = 'none';
    this.div.parentNode.insertBefore(div, this.div);
}

// Wikiwyg actions - public interface methods
Wikiwyg.prototype.saveChanges = function() {
    alert('Wikiwyg.prototype.saveChanges not subclassed');
}

// Wikiwyg actions - public methods
Wikiwyg.prototype.editMode = function() {
    this.current_mode = this.first_mode;
    this.current_mode.enableThis();
    this.current_mode.fromHtml(this.div.innerHTML);
    this.toolbarObject.resetModeSelector();
}

Wikiwyg.prototype.displayMode = function() {
    for (var key in this.mode_objects) {
        this.mode_objects[key].disableThis();
    }
    this.toolbarObject.disableThis();
    this.div.style.display = 'block';
    this.divHeight = this.div.clientHeight;
}

Wikiwyg.prototype.switchMode = function(new_mode_key) {
    var new_mode = this.mode_objects[new_mode_key];
    var old_mode = this.current_mode;
    var self = this;
    old_mode.toHtml(
        function(html) {
            new_mode.fromHtml(html);
            old_mode.disableThis();
            new_mode.enableThis();
            self.current_mode = new_mode;
        }
    );
}

Wikiwyg.prototype.cancelEdit = function() {
    this.displayMode();
}

Wikiwyg.prototype.fromHtml = function(html) {
    this.div.innerHTML = html;
}

// Class level helper methods
Wikiwyg.unique_id_base = 0;
Wikiwyg.createUniqueId = function() {
    return 'wikiwyg_' + Wikiwyg.unique_id_base++;
}

Wikiwyg.get_live_update = function(url, query_string, callback) {
    var req = new XMLHttpRequest()
    req.open('GET', url + '?' + query_string)
    req.onreadystatechange = function() {
        if (req.readyState == 4 && req.status == 200) {
            callback(req.responseText)
        }
    }
    req.send(null)
}

Wikiwyg.live_update = function(url, postdata, callback) {
    var req = new XMLHttpRequest()
    req.open('POST', url)
    req.onreadystatechange = function() {
        if (req.readyState == 4 && req.status == 200) {
            callback(req.responseText)
        }
    }
    req.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
    req.send(postdata)
}

/*==============================================================================
This class provides toolbar support
 =============================================================================*/
Wikiwyg.Toolbar = function() {}
Wikiwyg.Toolbar.prototype.initializeObject = function(wikiwyg) {
    this.wikiwyg = wikiwyg;
    this.div = document.createElement('div');
    this.div.innerHTML = '\
<table class="wikiwyg_background" \
       cellpadding="0" cellspacing="0" width="100%"> \
<tr><td colspan="100"></td></tr><tr></tr></table>';

    var trs = this.div.getElementsByTagName('tr');
    this.control_row = trs[0];
    this.button_row = trs[1];

    this.control_cell =
        this.control_row.getElementsByTagName('td')[0];

    this.setControls();
    this.setButtons();

    // XXX - Hack to get buttons flush left - use css
    var td = document.createElement('td');
    td.setAttribute('width', '100%');
    this.button_row.insertBefore(td, null);
}

Wikiwyg.Toolbar.prototype.enableThis = function() {
    this.div.style.display = 'block';
}

Wikiwyg.Toolbar.prototype.disableThis = function() {
    this.div.style.display = 'none';
}

Wikiwyg.Toolbar.prototype.setControls = function() {
    this.addControlItem('Save', 'saveChanges');
    this.addControlItem('Cancel', 'cancelEdit');
    this.addModeSelector();
}

Wikiwyg.Toolbar.prototype.setButtons = function() {
    this.add_styles();
    this.add_button('bold');
    this.add_button('italic');
    this.add_button('underline');
    this.add_button('strike', 'strikethrough', 'Strike Through');
    this.add_separator();
    this.add_button('hr', 'inserthorizontalrule', 'Horizontal Rule');
    this.add_separator();
    this.add_button('ordered', 'insertorderedlist',
                            'Ordered list');
    this.add_button('unordered', 'insertunorderedlist',
                            'Unordered list');
    this.add_separator();
    this.add_button('outdent');
    this.add_button('indent');
    this.add_separator();
    this.add_help_button();
}

Wikiwyg.Toolbar.prototype.add_button = function(type, command, label) {
    if (!command)
        command = type;
    if (!label)
        label = type;
    var td = document.createElement('td');
    var base = this.wikiwyg.config.baseUri;
    td.innerHTML =
      '<img class="wikiwyg_img" src="' + base + 'images/' + type + '.gif" \
      width="25" height="24" \
      alt="' + label + '" title="' + label + '">';

    var self = this;
    td.onclick = function() {
        self.wikiwyg.current_mode.process_command(command, null);
    };
    this.button_row.insertBefore(td, null);
}

Wikiwyg.Toolbar.prototype.add_help_button = function() {
    var td = document.createElement('td');
    var base = this.wikiwyg.config.baseUri;
    td.innerHTML = 
      '<a target="wikiwyg-about" href="http://www.wikiwyg.net/about/"> \
      <img class="wikiwyg_img" src="' + base + 'images/help.gif" \
      width="20" height="20" alt="Help" title="Help"></a>';

    var self = this;
    td.onclick = function() {
        var wikiwyg = self.wikiwyg;
        wikiwyg.current_mode.process_command(command, null);
    };
    this.button_row.insertBefore(td, null);
}

Wikiwyg.Toolbar.prototype.add_separator = function() {
    var td = document.createElement('td');
    var base = this.wikiwyg.config.baseUri;
    td.innerHTML = '\
<img class="wikiwyg_separator" src="' + base + 'images/blackdot.gif"\
     width="1" height="20" border="0" alt="">';
    this.button_row.insertBefore(td, null);
}

Wikiwyg.Toolbar.prototype.addControlItem = function(text, method) {
    var span = document.createElement('span');
    span.setAttribute('class', 'wikiwyg_control_link');

    var link = document.createElement('a');
    span.appendChild(link);

    link.setAttribute('href', '#');
    link.innerHTML = text;
    
    var self = this;
    link.onclick = function() { eval('self.wikiwyg.' + method + '()'); return false };

    this.control_cell.insertBefore(span, null);
}

Wikiwyg.Toolbar.prototype.resetModeSelector = function() {
    this.firstModeRadio.click();
}

Wikiwyg.Toolbar.prototype.addModeSelector = function() {
    var div = document.createElement('span');

    var radio_name = Wikiwyg.createUniqueId();
    for (var i in this.wikiwyg.modeList) {
        var class_name = this.wikiwyg.modeList[i];
        var mode_object = this.wikiwyg.mode_objects[class_name];
        var radio = document.createElement('input');
        if (!this.firstModeRadio)
            this.firstModeRadio = radio;

        radio.setAttribute('type', 'radio');
        radio.setAttribute('name', radio_name);
        var radio_id = Wikiwyg.createUniqueId();
        radio.setAttribute('id', radio_id);
        radio.setAttribute('value', mode_object.className);

        if (i == 0) {
            radio.setAttribute('checked', 'checked');
        }

        var self = this;
        radio.onclick = function() { 
            self.wikiwyg.switchMode(this.value);
        };

        var label = document.createElement('label');
        label.setAttribute('for', radio_id);
        label.innerHTML = mode_object.modeDescription;

        div.appendChild(radio);
        div.appendChild(label);
    }
    this.control_cell.insertBefore(div, null);
}

Wikiwyg.Toolbar.prototype.add_styles = function() {
    var td = document.createElement('td');
    td.innerHTML = '\
<select> \
<option value="">[Style]</option> \
<option value="p">Paragraph &lt;p&gt;</option> \
<option value="h1">Heading 1 &lt;h1&gt;</option> \
<option value="h2">Heading 2 &lt;h2&gt;</option> \
<option value="h3">Heading 3 &lt;h3&gt;</option> \
<option value="h4">Heading 4 &lt;h4&gt;</option> \
<option value="h5">Heading 5 &lt;h5&gt;</option> \
<option value="h6">Heading 6 &lt;h6&gt;</option> \
<option value="pre">Formatted &lt;pre&gt;</option> \
</select> \
';
    this.styleSelect = td.getElementsByTagName('select')[0];
    var self = this;
    this.styleSelect.onchange = function() { 
        self.wikiwyg.current_mode.set_style(this.value) 
    };
    this.button_row.insertBefore(td, null);
}

/*==============================================================================
Base class for Wikiwyg Mode classes
 =============================================================================*/
Wikiwyg.Mode = function() {}

Wikiwyg.Mode.prototype.enableThis = function() {
    this.div.style.display = 'block';
    this.wikiwyg.toolbarObject.enableThis();
    this.setupThis();
    this.wikiwyg.div.style.display = 'none';
}

Wikiwyg.Mode.prototype.disableThis = function() {
    this.div.style.display = 'none';
}

Wikiwyg.Mode.prototype.setupThis = function() {}

/*==============================================================================
This mode supports a DesignMode wysiwyg editor with toolbar buttons
 =============================================================================*/
Wikiwyg.Wysiwyg = function() {}

Wikiwyg.Wysiwyg.prototype = new Wikiwyg.Mode();

Wikiwyg.Wysiwyg.prototype.className = 'Wikiwyg.Wysiwyg';
Wikiwyg.Wysiwyg.prototype.modeDescription = 'Wysiwyg';

Wikiwyg.Wysiwyg.prototype.initializeObject = function(wikiwyg) {
    this.wikiwyg = wikiwyg;
    this.div = document.createElement('div');
    this.div.innerHTML =
        '<iframe width="100%"><html><body></body></html></iframe>';
    this.edit_iframe = this.div.getElementsByTagName('iframe')[0];
}

Wikiwyg.Wysiwyg.prototype.fromHtml = function(html) {
    this.edit_iframe.contentWindow.document.body.innerHTML = html;
}

Wikiwyg.Wysiwyg.prototype.rawHtml = function() {
    return this.edit_iframe.contentWindow.document.body.innerHTML;
}

Wikiwyg.Wysiwyg.prototype.toHtml = function(func) {
    var html = this.edit_iframe.contentWindow.document.body.innerHTML;
    func(html);
}

Wikiwyg.Wysiwyg.prototype.setupThis = function() {
    var height =
      this.wikiwyg.divHeight +
      this.wikiwyg.toolbarObject.div.clientHeight + 100;
    this.edit_iframe.height = height;

    var doc = this.edit_iframe.contentWindow.document;         
    this.edit_iframe.contentDocument.designMode = "on";
    doc.addEventListener("keypress", this.get_key_press_function(), true);
}

Wikiwyg.Wysiwyg.prototype.process_command = function(command, option) {
    var win = this.edit_iframe.contentWindow;         
    try {
        win.focus();
        win.document.execCommand(command, false, option);
        win.focus();
    } 
    catch (e) {
    }
}

Wikiwyg.Wysiwyg.prototype.get_key_press_function = function() {
    var self = this;
    return function(evt) {
        last_key = evt;
        if (! evt.ctrlKey) return;
        var key = String.fromCharCode(evt.charCode).toLowerCase();
        var cmd = '';
        switch (key) {
            case 'b': cmd = "bold"; break;
            case 'i': cmd = "italic"; break;
            case 'u': cmd = "underline"; break;
            case 'd': cmd = "strikethrough"; break;
        };

        if (cmd) {
            self.process_command(cmd, null);
            evt.preventDefault();
            evt.stopPropagation();
        }
    };
}

Wikiwyg.Wysiwyg.prototype.set_style = function(style_name) {
    var idx = this.wikiwyg.toolbarObject.styleSelect.selectedIndex;
    // First one is always a label
    if (idx != 0)
        this.process_command('formatblock', style_name);
    this.wikiwyg.toolbarObject.styleSelect.selectedIndex = 0;
}

/*==============================================================================
This mode supports a textarea editor with toolbar buttons.
 =============================================================================*/
Wikiwyg.Wikitext = function() {}

Wikiwyg.Wikitext.prototype = new Wikiwyg.Mode();

// XXX - we hate this but cannot find a way to get this dynamically
Wikiwyg.Wikitext.prototype.className = 'Wikiwyg.Wikitext';
Wikiwyg.Wikitext.prototype.modeDescription = 'Wikitext';

Wikiwyg.Wikitext.prototype.setupThis = function() {
    this.textarea.style.width = '100%';
    this.textarea.style.height = '200px';
}

Wikiwyg.Wikitext.prototype.initializeObject = function(wikiwyg) {
    this.wikiwyg = wikiwyg;
    this.div = document.createElement('div');
    this.div.innerHTML = '<textarea></textarea>';
    this.textarea = this.div.getElementsByTagName('textarea')[0];
    this.area = this.textarea;
}

Wikiwyg.Wikitext.prototype.toHtml = function(func) {
    var wikitext = this.textarea.value;
    this.convertWikitextToHtml(wikitext, func);
}

Wikiwyg.Wikitext.prototype.fromHtml = function(html) {
    this.textarea.value = 'Loading...';
    var textarea = this.textarea;
    this.convertHtmlToWikitext(
        html, 
        function(value) { textarea.value = value }
    );
}

// These two conversion routines are for demo purposes only. They need to
// be implemented in a subclass of Wikiwyg.Wikitext.
Wikiwyg.Wikitext.prototype.convertWikitextToHtml = function(wikitext, func) {
    func('<p>The Wikitext editor was invoked...</p>\n' + this.copyhtml);
}

Wikiwyg.Wikitext.prototype.convertHtmlToWikitext = function(html, func) {
    this.copyhtml = html;
    value = '\
This default implementation cannot convert HTML to Wikitext.\n\
\n\
But here is some sample demo text anyway:\n\
\n\
* *Bold*\n\
* /Italic/\n\
* _Underline_\n\
';
    func(value);
}

Wikiwyg.Wikitext.prototype.process_command = function(command, option) {
    eval("this.do_" + command + "()");
}

Wikiwyg.Wikitext.prototype.set_style = function(style_name) {
    var idx = this.wikiwyg.toolbarObject.styleSelect.selectedIndex;
    // First one is always a label
    if (idx != 0)
        this.process_command(style_name);
    this.wikiwyg.toolbarObject.styleSelect.selectedIndex = 0;
}

Wikiwyg.Wikitext.phrase_end_re = /[\s\.\:\;\,\!\?\(\)]/;

// XXX this is getting absurd
Wikiwyg.Wikitext.prototype.find_left = function(t, selection_start, matcher) {
    var substring = t.substr(selection_start - 1, 1);
    var nextstring = t.substr(selection_start - 2, 1);
    if (selection_start == 0) 
        return selection_start;
    if (substring.match(matcher)) {
        // special case for word.word
        if ((substring != '.') || (nextstring.match(/\s/))) 
            return selection_start;
    }
    return this.find_left(t, selection_start - 1, matcher);
}  

Wikiwyg.Wikitext.prototype.find_right = function(t, selection_end, matcher) {
    var substring = t.substr(selection_end, 1);
    var nextstring = t.substr(selection_end + 1, 1);
    if (selection_end >= t.length)
        return selection_end;
    if (substring.match(matcher)) {
        // special case for word.word
        if ((substring != '.') || (nextstring.match(/\s/)))
            return selection_end;
    }
    return this.find_right(t, selection_end + 1, matcher);
}

Wikiwyg.Wikitext.prototype.getLines = function() {
    t = this.area;
    var selection_start = t.selectionStart;
    var selection_end = t.selectionEnd;

    if (selection_start == null || selection_end == null)
        return false

    var our_text = t.value.replace(/\r/g, '');
    selection = our_text.substr(selection_start,
        selection_end - selection_start);

    selection_start = this.find_right(our_text, selection_start, /[^\r\n]/);
    selection_end = this.find_left(our_text, selection_end, /[^\r\n]/);

    this.selection_start = this.find_left(our_text, selection_start, /[\r\n]/);
    this.selection_end = this.find_right(our_text, selection_end, /[\r\n]/);
    t.setSelectionRange(selection_start, selection_end);
    t.focus();

    this.start = our_text.substr(0,this.selection_start);
    this.sel = our_text.substr(this.selection_start, this.selection_end -
        this.selection_start);
    this.finish = our_text.substr(this.selection_end, our_text.length);

    return true;
}

Wikiwyg.Wikitext.prototype.alarm_on = function() {
    var area = this.area;
    var background = area.style.background;
    area.style.background = '#f88';

    function alarm_off() {
        area.style.background = background;
    }

    window.setTimeout(alarm_off, 250);
    area.focus()
}

Wikiwyg.Wikitext.prototype.getWords = function() {
    function is_insane(selection) {
        return selection.match(/\r?\n(\r?\n|\*+ |\#+ |\=+ )/);
    }   

    t = this.area;
    var selection_start = t.selectionStart;
    var selection_end = t.selectionEnd;
    if (selection_start == null || selection_end == null)
        return false;
        
    var our_text = t.value.replace(/\r/g, '');
    selection = our_text.substr(selection_start,
        selection_end - selection_start);

    selection_start = this.find_right(our_text, selection_start, /(\S|\r?\n)/);
    if (selection_start > selection_end)
        selection_start = selection_end;
    selection_end = this.find_left(our_text, selection_end, /(\S|\r?\n)/);
    if (selection_end < selection_start)
        selection_end = selection_start;

    if (is_insane(selection)) {
        this.alarm_on();
        return false;
    }

    this.selection_start =
        this.find_left(our_text, selection_start, Wikiwyg.Wikitext.phrase_end_re);
    this.selection_end =
        this.find_right(our_text, selection_end, Wikiwyg.Wikitext.phrase_end_re);

    t.setSelectionRange(this.selection_start, this.selection_end);
    t.focus();

    this.start = our_text.substr(0,this.selection_start);
    this.sel = our_text.substr(this.selection_start, this.selection_end -
        this.selection_start);
    this.finish = our_text.substr(this.selection_end, our_text.length);

    return true;
}

Wikiwyg.Wikitext.prototype.markup_is_on = function(start, finish) {
    return (this.sel.match(start) && this.sel.match(finish));
}

Wikiwyg.Wikitext.prototype.clean_selection = function(start, finish) {
    this.sel = this.sel.replace(start, '');
    this.sel = this.sel.replace(finish, '');
}

Wikiwyg.Wikitext.prototype.toggle_same_format = function(start, finish) {
    start = this.cleanRE(start);
    finish = this.cleanRE(finish);
    var start_re = new RegExp('^' + start);
    var finish_re = new RegExp(finish + '$');
    if (this.markup_is_on(start_re, finish_re)) {
        this.clean_selection(start_re, finish_re);
        return true;
    }
    return false;
}

Wikiwyg.Wikitext.prototype.cleanRE = function(string) {
    string = string.replace(/([\^\*\[\]\{\}])/g, '\\' + "$1");
    return string;
}

Wikiwyg.Wikitext.prototype.setTextandSelection = function(text, start, end) {
    this.area.value = text;
    this.area.setSelectionRange(start, end);
}

Wikiwyg.Wikitext.prototype.addMarkupWords =
function(markup_start, markup_finish, example) {
    if (this.toggle_same_format(markup_start, markup_finish)) {
        this.selection_end = this.selection_end -
            (markup_start.length + markup_finish.length);
        markup_start = '';
        markup_finish = '';
    }
    if (this.sel.length == 0) {
        if (example)
            this.sel = example;
        var text = this.start + markup_start +
            this.sel + markup_finish + this.finish;
        var start = this.selection_start + markup_start.length;
        var end = this.selection_end + markup_start.length + this.sel.length;
        this.setTextandSelection(text, start, end);
    } else {
        var text = this.start + markup_start + this.sel +
            markup_finish + this.finish;
        var start = this.selection_start;
        var end = this.selection_end + markup_start.length +
            markup_finish.length;
        this.setTextandSelection(text, start, end);
    }
    this.area.focus();
}

Wikiwyg.Wikitext.prototype.addMarkupLines = function(markup_start) {
    var start_pattern = markup_start;
    start_pattern = start_pattern.replace(/(\=+) /, '$1');
    var already_set_re = new RegExp("^" + this.cleanRE(start_pattern) + " *",
        'gm');
    var other_markup_re = /^(\=+ *|\* |# )/gm;
    if (this.sel.match(already_set_re))
        this.sel = this.sel.replace(already_set_re, '');
    else if (this.sel.match(other_markup_re))
        this.sel = this.sel.replace(other_markup_re, markup_start);
    else if (this.sel.length > 0)
        this.sel = this.sel.replace(/^(.*\S+)/gm, markup_start + '$1');
    else
        this.sel = markup_start;
    var text = this.start + this.sel + this.finish;
    var start = this.selection_start;
    var end = this.selection_start + this.sel.length;
    this.setTextandSelection(text, start, end);
    this.area.focus();
}

Wikiwyg.Wikitext.prototype.startline = function(markup_start) {
    var scroll_top = this.area.scrollTop;
    if (this.getLines())
        this.addMarkupLines(markup_start + ' ');
    this.area.scrollTop = scroll_top;
}

Wikiwyg.Wikitext.prototype.boundword = function(markup_start, markup_finish, example) {
    var scroll_top = this.area.scrollTop;
    if (markup_finish == undefined)
        markup_finish = markup_start;
    if (this.getWords())
        this.addMarkupWords(markup_start, markup_finish, example);
    this.area.scrollTop = scroll_top;
}

Wikiwyg.Wikitext.prototype.do_bold = function() {
    this.boundword('*');
}

Wikiwyg.Wikitext.prototype.do_italic = function() {
    this.boundword('/');
}

Wikiwyg.Wikitext.prototype.do_underline = function() {
    this.boundword('_');
}

Wikiwyg.Wikitext.prototype.do_strikethrough = function() {
    this.boundword('-');
}

Wikiwyg.Wikitext.prototype.do_p = function() {
}

Wikiwyg.Wikitext.prototype.do_pre = function() {
}

Wikiwyg.Wikitext.prototype.do_h1 = function() {
    this.startline('=');
}

Wikiwyg.Wikitext.prototype.do_h2 = function() {
    this.startline('==');
}

Wikiwyg.Wikitext.prototype.do_h3 = function() {
    this.startline('===');
}

Wikiwyg.Wikitext.prototype.do_h4 = function() {
    this.startline('====');
}

Wikiwyg.Wikitext.prototype.do_h5 = function() {
    this.startline('=====');
}

Wikiwyg.Wikitext.prototype.do_h6 = function() {
    this.startline('======');
}

Wikiwyg.Wikitext.prototype.do_insertorderedlist = function() {
    this.startline('#');
}

Wikiwyg.Wikitext.prototype.do_insertunorderedlist = function() {
    this.startline('*');
}

Wikiwyg.Wikitext.prototype.do_dent = function(method) {
    var scroll_top = this.area.scrollTop;
    if (! this.getLines()) {
        this.area.scrollTop = scroll_top;
        return;
    }

    if (method(this)) {
        var text = this.start + this.sel + this.finish;
        var start = this.selection_start;
        var end = this.selection_start + this.sel.length;
        this.setTextandSelection(text, start, end);
    }
    this.area.focus();
}

Wikiwyg.Wikitext.prototype.do_indent = function() {
    this.do_dent(
        function(that) {
            if (that.sel == '') return false;
            that.sel = that.sel.replace(/^(([\*\-\#])+(?=\s))/gm, '$2$1');
            that.sel = that.sel.replace(/^([\>\=])/gm, '$1$1');
            that.sel = that.sel.replace(/^([^\>\*\-\#\=\r\n])/gm, '> $1');
            that.sel = that.sel.replace(/^\={7,}/gm, '======');
            return true;
        }
    )
}

Wikiwyg.Wikitext.prototype.do_outdent = function() {
    this.do_dent(
        function(that) {
            if (that.sel == '') return false;
            that.sel = that.sel.replace(/^([\>\*\-\#\=] ?)/gm, '');
            return true;
        }
    )
}

Wikiwyg.Wikitext.prototype.do_inserthorizontalrule = function() {
    var t = this.area;
    var scroll_top = t.scrollTop;
    var selection_start = t.selectionStart;
    var text = t.value;
    this.selection_start = this.find_right(text, selection_start, /\r?\n/);
    this.selection_end = this.selection_start;
    t.setSelectionRange(this.selection_start, this.selection_start);
    t.focus();

    this.start = t.value.substr(0, this.selection_start);
    this.finish = t.value.substr(this.selection_end, t.value.length);
    var text = this.start + '\n----' + this.finish;
    var start = this.selection_start + 5;
    var end = this.selection_end + 5;
    this.setTextandSelection(text, start, end);
    t.scrollTop = scroll_top;
}

/*==============================================================================
This mode supports a preview of current changes
 =============================================================================*/
Wikiwyg.Preview = function() {}

Wikiwyg.Preview.prototype = new Wikiwyg.Mode();

Wikiwyg.Preview.prototype.className = 'Wikiwyg.Preview';
Wikiwyg.Preview.prototype.modeDescription = 'Preview';

Wikiwyg.Preview.prototype.initializeObject = function(wikiwyg) {
    this.wikiwyg = wikiwyg;
    this.div = document.createElement('div');
    this.div.style.backgroundColor = 'lightyellow';
}

Wikiwyg.Preview.prototype.fromHtml = function(html) {
    this.div.innerHTML = html;
}

Wikiwyg.Preview.prototype.rawHtml = function() {
    return this.div.innerHTML;
}

Wikiwyg.Preview.prototype.toHtml = function(func) {
    func(this.div.innerHTML);
}
__css/wikiwyg.css__
.wikiwyg_img {
    background: #D3D3D3;
    border: 1px solid #D3D3D3;
    cursor: pointer;
    cursor: hand;
}

.wikiwyg_image_raised, .wikiwyg_img:hover {
    background: #D3D3D3;
    border: 1px outset;
    cursor: pointer;
    cursor: hand;
}

.wikiwyg_image_lowered, .wikiwyg_img:active {
    background: #D3D3D3;
    border: 1px inset;
    cursor: pointer;
    cursor: hand;
}

.wikiwyg_separator {
    margin: 0 4px 0 4px;
}

.wikiwyg_background {
    background: #D3D3D3;
    border: 1px outset;
    letter-spacing: 0;
    padding: 2px;
}

.wikiwyg_background tbody tr td, .wikiwyg_background tr td {
    background: #D3D3D3;
    padding: 0;
}

span.wikiwyg_control_link a {
    padding-right: 8px;
}
__images/blackdot.gif__
R0lGODlhAQABAIcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACH5BAAAAP8ALAAAAAABAAEA
AAgEAAEEBAA7
__images/bold.gif__
R0lGODlhGQAYAIABAAAAAP///yH5BAEAAAEALAAAAAAZABgAAAIojI+py+0Po5y0WgiyzlYbT4Hg
JHLhZp7Al0rlqrKwi7bXjef6zvd8AQA7
__images/hr.gif__
R0lGODlhGQAYAJECAJmZmTMzM////wAAACH5BAEAAAIALAAAAAAZABgAAAIelI+py+0Po5y02ouz
3ij4D4YOQJbmyaXqyrbuC7MFADs=
__images/link.gif__
R0lGODlhGQAYALMIAE1NTQCAAMDAwAAA/4CAgP///wAAgACAgP///wAAAAAAAAAAAAAAAAAAAAAA
AAAAACH5BAEAAAgALAAAAAAZABgAAARxEMlJq7046827n0QofiBxCGgAkEQhuEGseuHgDvgQEx0x
oAJDTDfj+ASygOEgXBlxyCTOufHlkocBVUMwXGUDA68DyAHOAAN6m0kDXi+Ay8XGvNd4Qd0ivwPv
BXsVd3hoemRwgXOHHmsIjiSRkpOUHxEAOw==
__images/image.gif__
R0lGODlhGQAYAIcAAAAAAAAAgAAA/wCAAAD/AAD///8AAP8A/4CAgMDAwP///wAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACH5BAMAAAcALAAAAAAZABgA
AAiPAA8IHEiwoMGDCBMqXMiwoUMAECNKRPBQgcWLFxFQZAhAQYKPID8iULBRYUeQAwaAHEly4ckE
AwgMAPBRokuPMFPSBKkAwE2QEEMm6PlTqICjHX2a9GggpIACApL+PND049EAUpcmEFhVIlGtA6vy
VJrwpMSdH7+WxSl07E2McC2SRXi2bkSHePPq3cv3YEAAOw==
__images/indent.gif__
R0lGODlhGQAYAJECAAAAAAAAgP///wAAACH5BAEAAAIALAAAAAAZABgAAAIxlI+py+0Po1Rg2ghy
1TzfLwRIxz2BaJBac7bgcR6khKbdC5aqh0t61QumhMSi8cgoAAA7
__images/table.gif__
R0lGODlhGQAYAIcAAAAAAAAzmf8A/8zMzP///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACH5BAMAAAIALAAAAAAZABgA
AAh4AAUIHEiwoMGDCBMqXMiwocOHCQFInEixIoCIATJq3LjxIkIAHENq9HgQAIEBBFKiVJnyJEmD
JleebClzwMuCAAbo3MmT502CMWkKVflzYFCWSF1G7Ml0Z1GBR2cmtRlRqtWaTwXkbMo0q8WvEyGK
HUu2rNmzZwMCADs=
__images/italic.gif__
R0lGODlhGQAYAJECAAAAAICAgP///wAAACH5BAEAAAIALAAAAAAZABgAAAIllI+py+0Po5y0Wgpy
viYHLgQb6IEiAAold6arpWnpTNf2jedLAQA7
__images/list.gif__
R0lGODlhGQAYAJECAAAAgAAAAP///wAAACH5BAEAAAIALAAAAAAZABgAAAIplI+py+0Po5y0HoAt
wsCED4IPp5UmRJppyI7ZCcdGWq6s6NDyzvf+UQAAOw==
__images/ordered.gif__
R0lGODlhGQAYAJECAAAAAAAAgP///wAAACH5BAEAAAIALAAAAAAZABgAAAIrlI+py+0Po5ww0BWs
Abz3eimZFpZMZiaax4KpML6yEb8k60Vkic7+Dww+CgA7
__images/outdent.gif__
R0lGODlhGQAYAJECAAAAgAAAAP///wAAACH5BAEAAAIALAAAAAAZABgAAAIxlI+py+0Po1Rh2hhy
1TzfLwBIxzmAeJBac7agcY6dhBrkC5aqh0t61QvahMSi8cgoAAA7
__images/strike.gif__
R0lGODlhFAAUAIAAAAAAAP///yH5BAEAAAEALAAAAAAUABQAAAInjI+py+0PHZggVDhPxtd0uVmR
FYLUSY1p1K3PVzZhzFTniOf6zjMFADs=
__images/underline.gif__
R0lGODlhGQAYAJECAAAAAICAgP///wAAACH5BAEAAAIALAAAAAAZABgAAAIulI+py+0Po5y0JoCB
yJri81Xh1nnlOI2opJbp6bJAIASrnFm6wvX7DwwKh0RgAQA7
__images/unordered.gif__
R0lGODlhGQAYAJECAAAAgAAAAP///wAAACH5BAEAAAIALAAAAAAZABgAAAIplI+py+0Po5y0HoAt
wsCED4IPp5UmRJppyI7ZCcdGWq6s6NDyzvf+UQAAOw==
__images/help.gif__
R0lGODlhFAAUAIAAAAAAAMDAwCH5BAEAAAEALAAAAAAUABQAAAIjjI+py+0fgJwwzgslok5vUCVe
aIEhdnIpeYzsC7dupcb2rRQAOw==
