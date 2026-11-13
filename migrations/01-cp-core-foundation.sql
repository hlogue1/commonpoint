CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE SCHEMA IF NOT EXISTS config;
CREATE SCHEMA IF NOT EXISTS build;
CREATE SCHEMA IF NOT EXISTS public;

CREATE TABLE config.content_type (
    id citext NOT NULL PRIMARY KEY,
    display citext,
    targetable_fields TEXT[] DEFAULT NULL
);

CREATE TABLE config.lang (
    id citext PRIMARY KEY NOT NULL,
    display citext NOT NULL,
    endonym citext DEFAULT NULL
);

INSERT INTO config.content_type VALUES ('lang', 'Language');

INSERT INTO config.lang (id, display, endonym) VALUES
    ('en', 'English', 'English'),
    ('aa', 'Afar', 'Qafaraf'),
    ('ab', 'Abkhazian', 'Аԥсшәа'),
    ('ae', 'Avestan', 'Avesta'),
    ('af', 'Afrikaans', 'Afrikaans'),
    ('ak', 'Akan', 'Akan'),
    ('am', 'Amharic', 'አማርኛ'),
    ('an', 'Aragonese', 'Aragonés'),
    ('ar', 'Arabic', 'العربية'),
    ('as', 'Assamese', 'অসমীয়া'),
    ('av', 'Avaric', 'Авар мацӀ'),
    ('ay', 'Aymara', 'Aymar aru'),
    ('az', 'Azerbaijani', 'Azərbaycan dili'),
    ('ba', 'Bashkir', 'Башҡорт теле'),
    ('be', 'Belarusian', 'Беларуская'),
    ('bg', 'Bulgarian', 'Български'),
    ('bi', 'Bislama', 'Bislama'),
    ('bm', 'Bambara', 'Bamanankan'),
    ('bn', 'Bengali', 'বাংলা'),
    ('bo', 'Tibetan', 'བོད་ཡིག'),
    ('br', 'Breton', 'Brezhoneg'),
    ('bs', 'Bosnian', 'Bosanski'),
    ('ca', 'Catalan', 'Català'),
    ('ce', 'Chechen', 'Нохчийн мотт'),
    ('ch', 'Chamorro', 'Chamoru'),
    ('co', 'Corsican', 'Corsu'),
    ('cr', 'Cree', 'ᓀᐦᐃᔭᐍᐏᐣ'),
    ('cs', 'Czech', 'Čeština'),
    ('cu', 'Church Slavic', 'Ѩзыкъ словѣньскъ'),
    ('cv', 'Chuvash', 'Чӑвашла'),
    ('cy', 'Welsh', 'Cymraeg'),
    ('da', 'Danish', 'Dansk'),
    ('de', 'German', 'Deutsch'),
    ('dv', 'Divehi', 'ދިވެހި'),
    ('dz', 'Dzongkha', 'རྫོང་ཁ'),
    ('ee', 'Ewe', 'Eʋegbe'),
    ('el', 'Greek', 'Ελληνικά'),
    ('eo', 'Esperanto', 'Esperanto'),
    ('es', 'Spanish', 'Español'),
    ('et', 'Estonian', 'Eesti'),
    ('eu', 'Basque', 'Euskara'),
    ('fa', 'Persian', 'فارسی'),
    ('ff', 'Fulah', 'Fulfulde'),
    ('fi', 'Finnish', 'Suomi'),
    ('fj', 'Fijian', 'Vosa Vakaviti'),
    ('fo', 'Faroese', 'Føroyskt'),
    ('fr', 'French', 'Français'),
    ('fy', 'Western Frisian', 'Frysk'),
    ('ga', 'Irish', 'Gaeilge'),
    ('gd', 'Scottish Gaelic', 'Gàidhlig'),
    ('gl', 'Galician', 'Galego'),
    ('gn', 'Guarani', 'Avañe''ẽ'),
    ('gu', 'Gujarati', 'ગુજરાતી'),
    ('gv', 'Manx', 'Gaelg'),
    ('ha', 'Hausa', 'Hausa'),
    ('he', 'Hebrew', 'עברית'),
    ('hi', 'Hindi', 'हिन्दी'),
    ('ho', 'Hiri Motu', 'Hiri Motu'),
    ('hr', 'Croatian', 'Hrvatski'),
    ('ht', 'Haitian Creole', 'Kreyòl ayisyen'),
    ('hu', 'Hungarian', 'Magyar'),
    ('hy', 'Armenian', 'Հայերեն'),
    ('hz', 'Herero', 'Otjiherero'),
    ('ia', 'Interlingua', 'Interlingua'),
    ('id', 'Indonesian', 'Bahasa Indonesia'),
    ('ie', 'Interlingue', 'Interlingue'),
    ('ig', 'Igbo', 'Asụsụ Igbo'),
    ('ii', 'Sichuan Yi', 'ꆈꌠꉙ'),
    ('ik', 'Inupiaq', 'Iñupiaq'),
    ('io', 'Ido', 'Ido'),
    ('is', 'Icelandic', 'Íslenska'),
    ('it', 'Italian', 'Italiano'),
    ('iu', 'Inuktitut', 'ᐃᓄᒃᑎᑐᑦ'),
    ('ja', 'Japanese', '日本語'),
    ('jv', 'Javanese', 'Basa Jawa'),
    ('ka', 'Georgian', 'ქართული'),
    ('kg', 'Kongo', 'Kikongo'),
    ('ki', 'Kikuyu', 'Gĩkũyũ'),
    ('kj', 'Kuanyama', 'Oshikwanyama'),
    ('kk', 'Kazakh', 'Қазақ тілі'),
    ('kl', 'Kalaallisut', 'Kalaallisut'),
    ('km', 'Khmer', 'ភាសាខ្មែរ'),
    ('kn', 'Kannada', 'ಕನ್ನಡ'),
    ('ko', 'Korean', '한국어'),
    ('kr', 'Kanuri', 'Kanuri'),
    ('ks', 'Kashmiri', 'كٲشُر'),
    ('ku', 'Kurdish', 'Kurdî'),
    ('kv', 'Komi', 'Коми кыв'),
    ('kw', 'Cornish', 'Kernewek'),
    ('ky', 'Kyrgyz', 'Кыргызча'),
    ('la', 'Latin', 'Latina'),
    ('lb', 'Luxembourgish', 'Lëtzebuergesch'),
    ('lg', 'Ganda', 'Luganda'),
    ('li', 'Limburgish', 'Limburgs'),
    ('ln', 'Lingala', 'Lingála'),
    ('lo', 'Lao', 'ລາວ'),
    ('lt', 'Lithuanian', 'Lietuvių'),
    ('lu', 'Luba-Katanga', 'Kiluba'),
    ('lv', 'Latvian', 'Latviešu'),
    ('mg', 'Malagasy', 'Malagasy'),
    ('mh', 'Marshallese', 'Kajin M̧ajeļ'),
    ('mi', 'Māori', 'Te reo Māori'),
    ('mk', 'Macedonian', 'Македонски'),
    ('ml', 'Malayalam', 'മലയാളം'),
    ('mn', 'Mongolian', 'Монгол'),
    ('mr', 'Marathi', 'मराठी'),
    ('ms', 'Malay', 'Bahasa Melayu'),
    ('mt', 'Maltese', 'Malti'),
    ('my', 'Burmese', 'မြန်မာဘာသာ'),
    ('na', 'Nauruan', 'Dorerin Naoero'),
    ('nb', 'Norwegian Bokmål', 'Norsk bokmål'),
    ('nd', 'North Ndebele', 'isiNdebele'),
    ('ne', 'Nepali', 'नेपाली'),
    ('ng', 'Ndonga', 'Owambo'),
    ('nl', 'Dutch', 'Nederlands'),
    ('nn', 'Norwegian Nynorsk', 'Norsk nynorsk'),
    ('no', 'Norwegian', 'Norsk'),
    ('nr', 'South Ndebele', 'isiNdebele'),
    ('nv', 'Navajo', 'Diné bizaad'),
    ('ny', 'Chichewa', 'Chichewa'),
    ('oc', 'Occitan', 'Occitan'),
    ('oj', 'Ojibwe', 'ᐊᓂᔑᓈᐯᒧᐎᓐ'),
    ('om', 'Oromo', 'Afaan Oromoo'),
    ('or', 'Odia', 'ଓଡ଼ିଆ'),
    ('os', 'Ossetian', 'Ирон æвзаг'),
    ('pa', 'Punjabi', 'ਪੰਜਾਬੀ'),
    ('pi', 'Pali', 'पालि'),
    ('pl', 'Polish', 'Polski'),
    ('ps', 'Pashto', 'پښتو'),
    ('pt', 'Portuguese', 'Português'),
    ('qu', 'Quechua', 'Runa Simi'),
    ('rm', 'Romansh', 'Rumantsch'),
    ('rn', 'Kirundi', 'Ikirundi'),
    ('ro', 'Romanian', 'Română'),
    ('ru', 'Russian', 'Русский'),
    ('rw', 'Kinyarwanda', 'Kinyarwanda'),
    ('sa', 'Sanskrit', 'संस्कृतम्'),
    ('sc', 'Sardinian', 'Sardu'),
    ('sd', 'Sindhi', 'سنڌي'),
    ('se', 'Northern Sami', 'Davvisámegiella'),
    ('sg', 'Sango', 'Sängö'),
    ('si', 'Sinhala', 'සිංහල'),
    ('sk', 'Slovak', 'Slovenčina'),
    ('sl', 'Slovenian', 'Slovenščina'),
    ('sm', 'Samoan', 'Gagana Samoa'),
    ('sn', 'Shona', 'chiShona'),
    ('so', 'Somali', 'Soomaali'),
    ('sq', 'Albanian', 'Shqip'),
    ('sr', 'Serbian', 'Српски'),
    ('ss', 'Swati', 'SiSwati'),
    ('st', 'Southern Sotho', 'Sesotho'),
    ('su', 'Sundanese', 'Basa Sunda'),
    ('sv', 'Swedish', 'Svenska'),
    ('sw', 'Swahili', 'Kiswahili'),
    ('ta', 'Tamil', 'தமிழ்'),
    ('te', 'Telugu', 'తెలుగు'),
    ('tg', 'Tajik', 'Тоҷикӣ'),
    ('th', 'Thai', 'ไทย'),
    ('ti', 'Tigrinya', 'ትግርኛ'),
    ('tk', 'Turkmen', 'Türkmençe'),
    ('tl', 'Tagalog', 'Tagalog'),
    ('tn', 'Tswana', 'Setswana'),
    ('to', 'Tongan', 'Lea faka-Tonga'),
    ('tr', 'Turkish', 'Türkçe'),
    ('ts', 'Tsonga', 'Xitsonga'),
    ('tt', 'Tatar', 'Татарча'),
    ('tw', 'Twi', 'Twi'),
    ('ty', 'Tahitian', 'Reo Tahiti'),
    ('ug', 'Uyghur', 'ئۇيغۇرچە'),
    ('uk', 'Ukrainian', 'Українська'),
    ('ur', 'Urdu', 'اردو'),
    ('uz', 'Uzbek', 'Oʻzbekcha'),
    ('ve', 'Venda', 'Tshivenḓa'),
    ('vi', 'Vietnamese', 'Tiếng Việt'),
    ('vo', 'Volapük', 'Volapük'),
    ('wa', 'Walloon', 'Walon'),
    ('wo', 'Wolof', 'Wolof'),
    ('xh', 'Xhosa', 'isiXhosa'),
    ('yi', 'Yiddish', 'ייִדיש'),
    ('yo', 'Yoruba', 'Yorùbá'),
    ('za', 'Zhuang', 'Saɯ cueŋƅ'),
    ('zh', 'Chinese', '中文'),
    ('zu', 'Zulu', 'isiZulu');

CREATE TABLE build.schema_extension (
    id UUID DEFAULT uuidv7() PRIMARY KEY,
    display_name citext UNIQUE,
    schema jsonb NOT NULL
);
INSERT INTO config.content_type VALUES ('schema_extension', 'Schema Extension');

CREATE TYPE config.name_use AS ENUM ('usual', 'official', 'temp', 'nickname', 'anonymous', 'old', 'maiden');

CREATE TYPE config.human_name AS
(
    use         config.name_use,
    family_name citext,
    given_name  citext[],
    prefix      citext[],
    suffix      citext[]
);

CREATE TYPE config.address_use AS ENUM ('home', 'work', 'temp', 'old', 'billing');

CREATE TYPE config.address AS
(
    use          config.address_use,
    content      citext[],
    municipality citext,
    locality     citext,
    region       citext,
    country      citext,
    postal_code  citext,
    is_physical  BOOL,
    is_mailing   BOOL
);

CREATE TYPE config.contact_system AS ENUM ('phone', 'fax', 'email', 'pager', 'url', 'sms', 'other');
CREATE TYPE config.contact_use AS ENUM ('home', 'work', 'temp', 'old', 'mobile');

CREATE TYPE config.contact_point AS
(
    system config.contact_system,
    use config.contact_use,
    value citext
);

CREATE TABLE build.downtime_region (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    name TEXT
);

INSERT INTO config.content_type VALUES ('downtime_region', 'Downtime Region');

CREATE TABLE build.data_flag (
    id CITEXT PRIMARY KEY NOT NULL,
    description TEXT NOT NULL UNIQUE
);

INSERT INTO build.data_flag VALUES
                          ('r', 'Restricted'),
                          ('substance', 'Substance Use'),
                          ('bh', 'Psychiatric/Behavioral Health'),
                          ('sogi', 'Sexual Orientation/Gender Identity'),
                          ('sti', 'Sexually Transmitted Infection Treatment'),
                          ('pay', 'Payment Operations'),
                          ('no', 'No disclosure without authorization'),
                          ('del', 'Delete after use'),
                          ('nofwd', 'No redisclosure without consent');