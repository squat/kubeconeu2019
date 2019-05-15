package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"io/ioutil"
	"log"
	"mime"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"strings"
	"sync"
	"time"

	"golang.org/x/image/font"
	"golang.org/x/image/font/basicfont"
	"golang.org/x/image/math/fixed"
)

func main() {
	port := flag.Int("port", 8081, "Port on which to listen.")
	stream := flag.String("stream", "", "URL to MJPEG stream.")
	label := flag.String("label", "", "URL to labeling service.")
	flag.Parse()
	s := NewStream()
	srv := &http.Server{
		Addr: fmt.Sprintf(":%d", *port),
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			mpr, err := readerFromURL(*stream)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				w.Write([]byte(err.Error()))
				return
			}
			stop := make(chan struct{})
			bc := make(chan []byte)
			go func() {
				var buf []byte
				for {
					select {
					case <-stop:
						return
					default:
						part, err := mpr.NextPart()
						if err != nil {
							log.Printf("failed to decode next part: %v\n", err)
						}
						buf, err = ioutil.ReadAll(part)
						if err != nil {
							log.Printf("failed to read part: %v\n", err)
						}
						select {
						case bc <- buf:
						default:
						}
					}
				}
			}()
			go func() {
				var buf []byte
				for {
					select {
					case <-stop:
						return
					case buf = <-bc:
						img, err := labelImage(*label, buf)
						if err != nil {
							log.Printf("failed to label image: %v\n", err)
							return
						}
						s.Update(img)
						if err != nil {
							log.Printf("failed to update stream: %v\n", err)
							return
						}
					}
				}
			}()
			s.ServeHTTP(w, r)
			close(stop)
		}),
	}
	log.Fatal(srv.ListenAndServe())
}

func readerFromURL(u string) (*multipart.Reader, error) {
	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil, err
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	_, param, err := mime.ParseMediaType(res.Header.Get("Content-Type"))
	if err != nil {
		return nil, err
	}
	return multipart.NewReader(res.Body, strings.Trim(param["boundary"], "-")), nil
}

func labelImage(url string, buf []byte) ([]byte, error) {
	b := new(bytes.Buffer)
	m := multipart.NewWriter(b)
	p, err := m.CreatePart(textproto.MIMEHeader{"Content-type": []string{"image/jpeg"}})
	if err != nil {
		return nil, err
	}
	if _, err = p.Write(buf); err != nil {
		return nil, err
	}
	if err := m.Close(); err != nil {
		return nil, err
	}

	req, err := http.NewRequest("POST", url, b)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", m.FormDataContentType())
	client := &http.Client{}
	res, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("got status %d", res.StatusCode)
	}
	body, err := ioutil.ReadAll(res.Body)
	if err != nil {
		return nil, err
	}

	l := &Label{}
	if err := json.Unmarshal(body, l); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response into labeling: %v", err)
	}
	src, err := jpeg.Decode(bytes.NewBuffer(buf))
	if err != nil {
		return nil, fmt.Errorf("failed to decode buffer as jpeg")
	}
	bo := src.Bounds()
	dst := image.NewNRGBA(image.Rect(0, 0, bo.Dx(), bo.Dy()))
	draw.Draw(dst, dst.Bounds(), src, bo.Min, draw.Src)
	red := color.RGBA{255, 0, 0, 255}
	for _, d := range l.Detections {
		if d.P < 0.5 {
			continue
		}
		rectangle(dst, red, int(l.X*d.X-(l.X*d.W/2)), int(l.Y*d.Y-(l.Y*d.H/2)), int(l.X*d.X+(l.X*d.W/2)), int(l.Y*d.Y+(l.Y*d.H/2)))
		addLabel(dst, red, int(l.X*d.X-(l.X*d.W/2)), int(l.Y*d.Y-(l.Y*d.H/2)), d.Label)
	}
	b.Reset()
	if err := jpeg.Encode(b, dst, nil); err != nil {
		return nil, fmt.Errorf("failed to encode buffer back to image: %v", err)
	}
	return b.Bytes(), nil
}

// Stream is an http.Handler capable of streaming MJPEGs.
type Stream struct {
	chs map[chan []byte]struct{}
	m   sync.Mutex
}

// NewStream created a new Stream.
func NewStream() *Stream {
	return &Stream{
		chs: make(map[chan []byte]struct{}),
	}
}

func (s *Stream) add(c chan []byte) {
	s.m.Lock()
	s.chs[c] = struct{}{}
	s.m.Unlock()
}

func (s *Stream) destroy(c chan []byte) {
	s.m.Lock()
	close(c)
	delete(s.chs, c)
	s.m.Unlock()
}

// Update sends the given buffer to all ready clients.
func (s *Stream) Update(buf []byte) {
	s.m.Lock()
	defer s.m.Unlock()
	for c := range s.chs {
		select {
		case c <- buf:
		default:
		}
	}
}

// ServeHTTP implements the http.Handler interface.
func (s *Stream) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	c := make(chan []byte)
	s.add(c)
	defer s.destroy(c)

	m := multipart.NewWriter(w)
	defer m.Close()

	w.Header().Set("Content-Type", "multipart/x-mixed-replace; boundary="+m.Boundary())
	w.Header().Set("Connection", "close")
	h := textproto.MIMEHeader{}
	st := fmt.Sprint(time.Now().Unix())
	for {
		buf, ok := <-c
		if !ok {
			break
		}
		if buf == nil {
			continue
		}
		h.Set("Content-Type", "image/jpeg")
		h.Set("Content-Length", fmt.Sprint(len(buf)))
		h.Set("X-StartTime", st)
		h.Set("X-TimeStamp", fmt.Sprint(time.Now().Unix()))
		p, err := m.CreatePart(h)
		if err != nil {
			log.Printf("failed to create part: %v\n", err)
			break
		}
		if _, err = p.Write(buf); err != nil {
			log.Printf("failed to write to part: %v\n", err)
			break
		}
		if flusher, ok := p.(http.Flusher); ok {
			flusher.Flush()
		}
	}
}

// Close cleans up the Stream.
func (s *Stream) Close() {
	s.m.Lock()
	defer s.m.Unlock()
	for c := range s.chs {
		close(c)
		delete(s.chs, c)
	}
}

// Label represents a result from the labeling service.
type Label struct {
	X          float64     `json:"x"`
	Y          float64     `json:"y"`
	Detections []Detection `json:"detections"`
}

// Detection represents a single detection within a label result.
type Detection struct {
	Label string  `json:"label"`
	P     float64 `json:"p"`
	X     float64 `json:"x"`
	Y     float64 `json:"y"`
	W     float64 `json:"w"`
	H     float64 `json:"h"`
}

func horizontal(img draw.Image, c color.Color, x1, y, x2 int) {
	for ; x1 <= x2; x1++ {
		img.Set(x1, y, c)
		img.Set(x1, y-1, c)
		img.Set(x1, y+1, c)
	}
}

func vertical(img draw.Image, c color.Color, x, y1, y2 int) {
	for ; y1 <= y2; y1++ {
		img.Set(x, y1, c)
		img.Set(x-1, y1, c)
		img.Set(x+1, y1, c)
	}
}

func rectangle(img draw.Image, c color.Color, x1, y1, x2, y2 int) {
	horizontal(img, c, x1, y1, x2)
	horizontal(img, c, x1, y2, x2)
	vertical(img, c, x1, y1, y2)
	vertical(img, c, x2, y1, y2)
}

func addLabel(img draw.Image, c color.Color, x, y int, label string) {
	point := fixed.Point26_6{X: fixed.Int26_6(x * 64), Y: fixed.Int26_6((y - 2) * 64)}
	d := &font.Drawer{
		Dst:  img,
		Src:  image.NewUniform(c),
		Face: basicfont.Face7x13,
		Dot:  point,
	}
	d.DrawString(label)
}
