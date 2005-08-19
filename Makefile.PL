use inc::Module::Install;

name('Kwiki-Wikiwyg');
author('Brian Ingerson <ingy@cpan.org>');
abstract('Wysiwyg Editing for Kwiki');
license('perl');
version_from('lib/Kwiki/Wikiwyg.pm');

requires(qw(
    perl 5.6.1
));

check_nmake();

&WriteAll();
