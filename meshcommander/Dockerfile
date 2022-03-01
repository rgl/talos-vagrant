FROM node:16-alpine3.15
WORKDIR /app
RUN npm install meshcommander@0.9.3-b
EXPOSE 4000
CMD ["/app/node_modules/.bin/meshcommander", "--any", "--port", "4000"]
