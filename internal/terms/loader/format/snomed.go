// SPDX-License-Identifier: GPL-3.0-or-later

package format

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"

	"github.com/hlogue1/commonpoint/internal/terms/loader/tabular"
)

// Well-known SNOMED CT metadata ids.
const (
	SnomedFSNType             = "900000000000003001"
	SnomedInferred            = "900000000000011006"
	SnomedIsA                 = "116680003"
	SnomedInternationalModule = "900000000000207008"
	SnomedUSModule            = "731000124108"
)

// RF2 edition namespaces as they appear in file names, mapped to the edition module id used
// in the FHIR version URI http://snomed.info/sct/<module>/version/<date>.
var snomedEditionModules = map[string]string{
	"INT":       SnomedInternationalModule,
	"US1000124": SnomedUSModule,
}

var (
	rf2Base    = []string{"id", "effectiveTime", "active", "moduleId", "refsetId", "referencedComponentId"}
	rf2Concept = []string{"id", "effectiveTime", "active", "moduleId", "definitionStatusId"}
	rf2Desc    = []string{"id", "effectiveTime", "active", "moduleId", "conceptId", "languageCode", "typeId", "term", "caseSignificanceId"}
	rf2Rel     = []string{"id", "effectiveTime", "active", "moduleId", "sourceId", "destinationId", "relationshipGroup", "typeId", "characteristicTypeId", "modifierId"}
	rf2Conc    = []string{"id", "effectiveTime", "active", "moduleId", "sourceId", "value", "relationshipGroup", "typeId", "characteristicTypeId", "modifierId"}
)

func rf2(cols ...string) tabular.Layout {
	return tabular.Layout{Kind: tabular.Delimited, Sep: "\t", Header: true, ExactHeader: true, Columns: cols}
}

func refset(extra ...string) tabular.Layout {
	return rf2(append(append([]string{}, rf2Base...), extra...)...)
}

func rx(p string) *regexp.Regexp { return regexp.MustCompile(`(?i)(^|/)` + p + `$`) }

var snomedConceptName = regexp.MustCompile(`(?i)sct2_Concept_Snapshot_([A-Za-z0-9]+)_(\d{8})\.txt$`)

var SnomedRF2 = register(&Format{
	Name:         "snomed-rf2",
	Title:        "SNOMED CT RF2 Snapshot (International, US and other editions; layered packages)",
	Publisher:    "SNOMED International / NLM",
	Origin:       Vendor,
	CodeSystems:  []string{"snomed"},
	SourceFormat: "SOURCE_FORMAT_SNOMED_RF2_SNAPSHOT",
	Files: []FileSpec{
		{ID: "concept", Pattern: rx(`sct2_Concept_Snapshot_[^/]*\.txt`), Required: true, Multiple: true, Layout: rf2(rf2Concept...)},
		{ID: "description", Pattern: rx(`sct2_Description_Snapshot-[^/]*\.txt`), Required: true, Multiple: true, Layout: rf2(rf2Desc...)},
		{ID: "text_definition", Pattern: rx(`sct2_TextDefinition_Snapshot-[^/]*\.txt`), Multiple: true, Layout: rf2(rf2Desc...)},
		{ID: "relationship", Pattern: rx(`sct2_Relationship_Snapshot_[^/]*\.txt`), Required: true, Multiple: true, Layout: rf2(rf2Rel...)},
		{ID: "relationship_concrete", Pattern: rx(`sct2_RelationshipConcreteValues_Snapshot_[^/]*\.txt`), Multiple: true, Layout: rf2(rf2Conc...)},
		{ID: "language", Pattern: rx(`der2_cRefset_LanguageSnapshot-[^/]*\.txt`), Required: true, Multiple: true, Layout: refset("acceptabilityId")},
		{ID: "simple", Pattern: rx(`der2_Refset_SimpleSnapshot_[^/]*\.txt`), Multiple: true, Layout: refset()},
		{ID: "association", Pattern: rx(`der2_cRefset_Association(Reference)?Snapshot_[^/]*\.txt`), Multiple: true, Layout: refset("targetComponentId")},
		{ID: "attribute_value", Pattern: rx(`der2_cRefset_AttributeValueSnapshot_[^/]*\.txt`), Multiple: true, Layout: refset("valueId")},
		{ID: "extended_map", Pattern: rx(`der2_iisssccRefset_ExtendedMapSnapshot_[^/]*\.txt`), Multiple: true,
			Layout: refset("mapGroup", "mapPriority", "mapRule", "mapAdvice", "mapTarget", "correlationId", "mapCategoryId")},
		{ID: "simple_map", Pattern: rx(`der2_sRefset_SimpleMapSnapshot_[^/]*\.txt`), Multiple: true, Layout: refset("mapTarget")},
		{ID: "module_dependency", Pattern: rx(`der2_ssRefset_ModuleDependencySnapshot_[^/]*\.txt`), Multiple: true,
			Layout: refset("sourceEffectiveTime", "targetEffectiveTime")},
		{ID: "core_problem_list", Pattern: rx(`SNOMEDCT_CORE_SUBSET_[^/]*\.txt`), Multiple: true,
			Layout: tabular.Layout{Kind: tabular.Delimited, Sep: "|", Header: true, Required: []string{"SNOMED_CID", "SNOMED_FSN"}}},
	},
	Sniff: sniffSnomed,
	New:   func(Options) Checker { return newSnomedChecker() },
})

func sniffSnomed(sel *Selection, md *Metadata, _ Options) {
	type pkg struct{ ns, date string }
	var pkgs []pkg
	for _, f := range sel.Files["concept"] {
		if m := snomedConceptName.FindStringSubmatch(f.Name); m != nil {
			pkgs = append(pkgs, pkg{m[1], m[2]})
		}
	}
	if len(pkgs) == 0 {
		return
	}
	// The newest package names the version; on a tie an extension wins over INT.
	sort.SliceStable(pkgs, func(i, j int) bool {
		if pkgs[i].date != pkgs[j].date {
			return pkgs[i].date > pkgs[j].date
		}
		return pkgs[i].ns != "INT" && pkgs[j].ns == "INT"
	})
	for _, p := range pkgs {
		md.Packages = append(md.Packages, p.ns+" "+p.date)
	}
	top := pkgs[0]
	md.Version = top.date
	if t, ok := yyyymmdd(top.date); ok {
		md.ReleaseDate = isoDate(t)
	}
	if mod, ok := snomedEditionModules[top.ns]; ok {
		md.FHIRVersionURI = fmt.Sprintf("http://snomed.info/sct/%s/version/%s", mod, top.date)
	} else {
		md.Notes = append(md.Notes, "unknown edition namespace "+top.ns+"; pass --fhir-version-uri")
	}
	if len(pkgs) > 1 {
		md.Notes = append(md.Notes, "multiple packages: install layers them, keeping the latest effectiveTime per component id")
	}
}

type snomedChecker struct {
	concepts        map[uint64]struct{}
	active          int64
	activeDescs     int64
	fsn             int64
	inferredIsA     int64
	missingConcepts int64
}

func newSnomedChecker() *snomedChecker {
	return &snomedChecker{concepts: make(map[uint64]struct{}, 1<<20)}
}

func (s *snomedChecker) known(id string) bool {
	n, err := strconv.ParseUint(id, 10, 64)
	if err != nil {
		return false
	}
	_, ok := s.concepts[n]
	return ok
}

func (s *snomedChecker) common(c *Ctx, rec tabular.Record) bool {
	ok := true
	if _, valid := yyyymmdd(rec.Get("effectiveTime")); !valid {
		c.Errorf(rec.Line, "bad_effective_time", "effectiveTime %q is not YYYYMMDD", rec.Get("effectiveTime"))
		ok = false
	}
	if a := rec.Get("active"); a != "0" && a != "1" {
		c.Errorf(rec.Line, "bad_active", "active %q is not 0 or 1", a)
		ok = false
	}
	if !IsSCTID(rec.Get("moduleId")) {
		c.Errorf(rec.Line, "bad_sctid", "moduleId %q is not a valid SCTID", rec.Get("moduleId"))
		ok = false
	}
	return ok
}

func (s *snomedChecker) sctid(c *Ctx, rec tabular.Record, col, kind string) {
	v := rec.Get(col)
	k := SCTIDKind(v)
	switch {
	case k == "":
		c.Errorf(rec.Line, "bad_sctid", "%s %q is not a valid SCTID", col, v)
	case kind != "" && k != kind:
		c.Errorf(rec.Line, "bad_sctid_partition", "%s %q is a %s id; expected a %s id", col, v, k, kind)
	}
}

func (s *snomedChecker) concept(c *Ctx, rec tabular.Record, col string) {
	v := rec.Get(col)
	if !IsSCTID(v) {
		c.Errorf(rec.Line, "bad_sctid", "%s %q is not a valid SCTID", col, v)
		return
	}
	if !s.known(v) {
		s.missingConcepts++
		c.Errorf(rec.Line, "unknown_concept", "%s %s is not in any concept file", col, v)
	}
}

func (s *snomedChecker) Row(c *Ctx, rec tabular.Record) {
	s.common(c, rec)
	active := rec.Get("active") == "1"
	switch c.Spec.ID {
	case "concept":
		id := rec.Get("id")
		s.sctid(c, rec, "id", PartitionConcept)
		if n, err := strconv.ParseUint(id, 10, 64); err == nil {
			s.concepts[n] = struct{}{}
		}
		s.sctid(c, rec, "definitionStatusId", PartitionConcept)
		if active {
			s.active++
		}
	case "description", "text_definition":
		s.sctid(c, rec, "id", PartitionDescription)
		s.concept(c, rec, "conceptId")
		s.sctid(c, rec, "typeId", PartitionConcept)
		if rec.Get("term") == "" {
			c.Errorf(rec.Line, "empty_term", "description %s has an empty term", rec.Get("id"))
		}
		if rec.Get("languageCode") == "" {
			c.Errorf(rec.Line, "empty_language", "description %s has no languageCode", rec.Get("id"))
		}
		if active && c.Spec.ID == "description" {
			s.activeDescs++
			if rec.Get("typeId") == SnomedFSNType {
				s.fsn++
			}
		}
	case "relationship", "relationship_concrete":
		s.sctid(c, rec, "id", PartitionRelationship)
		s.concept(c, rec, "sourceId")
		s.concept(c, rec, "typeId")
		if c.Spec.ID == "relationship" {
			s.concept(c, rec, "destinationId")
			if active && rec.Get("typeId") == SnomedIsA && rec.Get("characteristicTypeId") == SnomedInferred {
				s.inferredIsA++
			}
		} else if v := rec.Get("value"); v == "" || (v[0] != '#' && v[0] != '"') {
			c.Errorf(rec.Line, "bad_concrete_value", "value %q must start with # (number) or \" (string)", v)
		}
		if _, ok := atoi(rec.Get("relationshipGroup")); !ok {
			c.Errorf(rec.Line, "bad_group", "relationshipGroup %q is not an integer", rec.Get("relationshipGroup"))
		}
		s.sctid(c, rec, "characteristicTypeId", PartitionConcept)
	case "core_problem_list":
		if !IsSCTID(rec.Get("SNOMED_CID")) {
			c.Errorf(rec.Line, "bad_sctid", "SNOMED_CID %q is not a valid SCTID", rec.Get("SNOMED_CID"))
		}
	default: // reference sets
		if !uuidRe.MatchString(rec.Get("id")) {
			c.Errorf(rec.Line, "bad_member_id", "refset member id %q is not a UUID", rec.Get("id"))
		}
		s.sctid(c, rec, "refsetId", PartitionConcept)
		if c.Spec.ID == "language" {
			s.sctid(c, rec, "referencedComponentId", PartitionDescription)
			s.sctid(c, rec, "acceptabilityId", PartitionConcept)
		}
		if c.Spec.ID == "extended_map" {
			if _, ok := atoi(rec.Get("mapGroup")); !ok {
				c.Errorf(rec.Line, "bad_map_group", "mapGroup %q is not an integer", rec.Get("mapGroup"))
			}
			if _, ok := atoi(rec.Get("mapPriority")); !ok {
				c.Errorf(rec.Line, "bad_map_priority", "mapPriority %q is not an integer", rec.Get("mapPriority"))
			}
		}
	}
}

func (s *snomedChecker) Finish(c *Ctx) {
	c.Meta.AddCount("concepts", int64(len(s.concepts)))
	c.Meta.AddCount("active concepts", s.active)
	c.Meta.AddCount("active descriptions", s.activeDescs)
	c.Meta.AddCount("active FSNs", s.fsn)
	c.Meta.AddCount("active inferred is-a relationships", s.inferredIsA)
	if s.active > 0 && s.inferredIsA == 0 {
		c.Errorf(0, "no_hierarchy", "no active inferred is-a (%s) relationships; the closure would be empty", SnomedIsA)
	}
	if s.fsn < s.active {
		c.Warnf(0, "missing_fsn", "%d active concepts but only %d active FSNs", s.active, s.fsn)
	}
}
