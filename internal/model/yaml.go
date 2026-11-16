package model

import (
	"bytes"
	"fmt"
	"reflect"

	"golang.org/x/text/unicode/norm"
	"gopkg.in/yaml.v3"
)

// Kódy chyb.
const (
	ErrYAMLInvalid = "YAML_INVALID"
)

// MarshalYAML zakóduje v do YAML s odsazením 2 mezery (víceřádkové řetězce jako blok `|`).
func MarshalYAML(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	if err := enc.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// UnmarshalYAML dekóduje YAML do v a normalizuje řetězce do NFC.
func UnmarshalYAML(data []byte, v any) error {
	if err := yaml.Unmarshal(data, v); err != nil {
		return fmt.Errorf("%s: %w", ErrYAMLInvalid, err)
	}
	NormalizeNFC(v)
	return nil
}

// NormalizeNFC převede všechny řetězce ve struktuře (přes ukazatel) do Unicode NFC.
func NormalizeNFC(v any) {
	normalize(reflect.ValueOf(v))
}

func normalize(v reflect.Value) {
	switch v.Kind() {
	case reflect.Pointer, reflect.Interface:
		if !v.IsNil() {
			normalize(v.Elem())
		}
	case reflect.Struct:
		for i := 0; i < v.NumField(); i++ {
			if v.Type().Field(i).IsExported() {
				normalize(v.Field(i))
			}
		}
	case reflect.Slice, reflect.Array:
		for i := 0; i < v.Len(); i++ {
			normalize(v.Index(i))
		}
	case reflect.String:
		if v.CanSet() {
			if s := v.String(); !norm.NFC.IsNormalString(s) {
				v.SetString(norm.NFC.String(s))
			}
		}
	}
}
